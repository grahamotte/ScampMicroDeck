class Linear
  HOST = "https://api.linear.app/graphql"
  ROBOT = "🤖"
  STATUSES = [
    { name: "Backlog", type: "backlog", color: "#f2994a" },
    { name: "Planned", type: "unstarted", color: "#95a2b3" },
    { name: "#{ROBOT} Ready", type: "started", color: "#26b5ce" },
    { name: "Working", type: "started", color: "#f2c94c" },
    { name: "Review", type: "started", color: "#f2994a" },
    { name: "#{ROBOT} Approved", type: "started", color: "#4cb782" },
    { name: "Completed", type: "completed", color: "#5e6ad2" },
    { name: "Canceled", type: "canceled", color: "#95a2b3" },
  ].freeze
  TAGS = [
    { name: "working", color: "#f2c94c" },
    { name: "skip review", color: "#4cb782" },
    { name: "runner: interactive", color: "#bb87fc" },
    { name: "runner: openchamber", color: "#bb87fc" },
    { name: "runner: t3", color: "#bb87fc" },
    { name: "variant: low", color: "#4cb782" },
    { name: "variant: medium", color: "#4cb782" },
    { name: "variant: high", color: "#4cb782" },
    { name: "variant: xhigh", color: "#4cb782" },
    { name: "variant: max", color: "#4cb782" },
    { name: "variant: ultra", color: "#4cb782" },
    { name: "variant: ultrathink", color: "#4cb782" },
    { name: "model: openai/gpt-6.1-sol", color: "#26b5ce" },
    { name: "model: openai/gpt-6-astra", color: "#26b5ce" },
    { name: "model: anthropic/claude-opus-5-5", color: "#26b5ce" },
    { name: "model: anthropic/claude-sonnet-5-5", color: "#26b5ce" },
    { name: "model: xai/grok-4.7", color: "#26b5ce" },
    { name: "model: google/gemini-3.1-pro", color: "#26b5ce" },
    { name: "model: cursor/composer-2.5", color: "#26b5ce" },
    { name: "model: cursor/grok-4.7", color: "#26b5ce" },
  ].freeze

  class << self
    def reset
      @team_id = nil
      @states = nil
      @tags = nil
    end

    def issues(filter: nil)
      nodes = []
      after = nil
      loop do
        page = graphql(
          ISSUES_QUERY,
          { teamId: team_id, after:, filter: }.compact,
        ).fetch(:team).fetch(:issues)
        nodes.concat(page.fetch(:nodes))
        break unless page.dig(:pageInfo, :hasNextPage)

        after = page.dig(:pageInfo, :endCursor)
        break if after.blank?
      end
      nodes
    end

    def move(item, column)
      graphql(
        ISSUE_UPDATE_MUTATION,
        { id: item.fetch(:id), input: { stateId: state_id(column) } },
      )
    end

    def tag(item, name)
      graphql(
        ISSUE_UPDATE_MUTATION,
        { id: item.fetch(:id), input: { addedLabelIds: [ tag_id(name) ] } },
      )
    end

    def untag(item, name)
      graphql(
        ISSUE_UPDATE_MUTATION,
        { id: item.fetch(:id), input: { removedLabelIds: [ tag_id(name) ] } },
      )
    end

    def tagged?(item, name)
      nodes = item.dig(:labels, :nodes)
      return false if nodes.blank?

      nodes.any? { |label| label[:name].to_s.downcase == name.to_s.downcase }
    end

    def column(item)
      state = item[:state]
      return column_key(state[:name]) if state.is_a?(Hash) && state[:name].present?
      return states_by_id[state] if state.present?

      nil
    end

    def state_names(*columns)
      STATUSES
        .select { |status| columns.include?(column_key(status[:name])) }
        .flat_map { |status| [ status[:name], status[:name].delete_prefix(ROBOT).strip ] }
        .uniq
    end

    def identifier(item)
      item.fetch(:identifier)
    end

    def url(item)
      item.fetch(:url)
    end

    def runner(item)
      labeled(item, "runner")
    end

    def model(item)
      labeled(item, "model")
    end

    def variant(item)
      labeled(item, "variant")
    end

    def sync_statuses
      current = state_nodes
      used_ids = []
      floor = current.map { |state| state[:position].to_f }.max || -1000.0

      STATUSES.each do |want|
        existing = match_state(current, want, used_ids)
        if existing
          used_ids << existing.fetch(:id)
          input = {}
          input[:name] = want[:name] if existing[:name] != want[:name]
          input[:color] = want[:color] if existing[:color] != want[:color]
          input[:description] = nil if existing[:description].is_a?(String)
          if input.present?
            graphql(STATE_UPDATE_MUTATION, { id: existing.fetch(:id), input: })
            puts "renamed #{existing[:name]} to #{want[:name]}" if input[:name].present?
          end
        else
          floor = next_position(floor)
          graphql(
            STATE_CREATE_MUTATION,
            {
              input: {
                teamId: team_id,
                name: want[:name],
                type: want[:type],
                color: want[:color],
                position: floor,
              },
            },
          )
          puts "created #{want[:name]}"
        end
      end

      current.each do |state|
        next if used_ids.include?(state.fetch(:id))
        next if state[:type] == "duplicate"

        begin
          graphql(STATE_ARCHIVE_MUTATION, { id: state.fetch(:id) })
          puts "removed #{state[:name]}"
        rescue StandardError => error
          raise unless error.message.to_s.include?("reserved")
        end
      end

      sync_status_positions(state_nodes)

      @states = nil
    end

    def sync_tags
      current = tag_nodes
      legacy = current.find { |tag| tag[:name].to_s.casecmp?("interactive") }
      if legacy.present? && current.any? { |tag| tag[:name].to_s.casecmp?("runner: interactive") }
        raise "Merge the interactive and runner: interactive labels before syncing"
      end
      used_ids = []
      TAGS.each do |want|
        existing = current.find { |tag| tag[:name].to_s.downcase == want[:name].downcase }
        existing ||= legacy if want[:name] == "runner: interactive"
        if existing
          used_ids << existing.fetch(:id)
          input = {}
          input[:name] = want[:name] unless existing[:name].to_s.casecmp?(want[:name])
          input[:color] = want[:color] if existing[:color] != want[:color]
          next if input.blank?

          graphql(TAG_UPDATE_MUTATION, { id: existing.fetch(:id), input: })
          puts "renamed #{existing[:name]} to #{want[:name]}" if input[:name].present?
        else
          graphql(
            TAG_CREATE_MUTATION,
            {
              input: {
                teamId: team_id,
                name: want[:name],
                color: want[:color],
              },
            },
          )
          puts "created #{want[:name]} tag"
        end
      end
      current.each do |tag|
        next if used_ids.include?(tag.fetch(:id))
        next if TAGS.any? { |want| want[:name].casecmp?(tag[:name].to_s) }
        next if tag[:team].present? && tag.dig(:team, :id) != team_id

        graphql(TAG_DELETE_MUTATION, { id: tag.fetch(:id) })
        puts "removed #{tag[:name]} tag"
      end
      @tags = nil
    end

    def sync_git_automations
      git_automation_nodes.each do |rule|
        graphql(GIT_AUTOMATION_STATE_DELETE_MUTATION, { id: rule.fetch(:id) })
        puts "removed git automation #{rule.fetch(:event)} (#{rule.dig(:state, :name)})"
      end
    end

    private

    def column_key(name)
      name.to_s.delete_prefix(ROBOT).strip.downcase
    end

    def labeled(item, key)
      nodes = item.dig(:labels, :nodes)
      return nil if nodes.blank?

      prefix = "#{key}:"
      nodes.each do |label|
        name = label[:name].to_s
        next unless name.downcase.start_with?(prefix)

        value = name.split(":", 2).last.strip
        return value if value.present?
      end
      nil
    end

    WORKSPACE_QUERY = <<~GQL
      query Workspace($key: String!) {
        organization {
          urlKey
        }
        teams(filter: { key: { eq: $key } }) {
          nodes {
            id
            key
          }
        }
      }
    GQL

    STATES_QUERY = <<~GQL
      query States($teamId: String!) {
        team(id: $teamId) {
          states {
            nodes {
              id
              name
              type
              color
              description
              position
            }
          }
        }
      }
    GQL

    ISSUES_QUERY = <<~GQL
      query Issues($teamId: String!, $after: String, $filter: IssueFilter) {
        team(id: $teamId) {
          issues(first: 100, after: $after, filter: $filter) {
            nodes {
              id
              identifier
              title
              url
              state {
                id
                name
              }
              labels {
                nodes {
                  id
                  name
                }
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    GQL

    ISSUE_UPDATE_MUTATION = <<~GQL
      mutation IssueUpdate($id: String!, $input: IssueUpdateInput!) {
        issueUpdate(id: $id, input: $input) {
          success
          issue {
            id
            identifier
            title
            description
          }
        }
      }
    GQL

    STATE_CREATE_MUTATION = <<~GQL
      mutation WorkflowStateCreate($input: WorkflowStateCreateInput!) {
        workflowStateCreate(input: $input) {
          success
        }
      }
    GQL

    STATE_UPDATE_MUTATION = <<~GQL
      mutation WorkflowStateUpdate($id: String!, $input: WorkflowStateUpdateInput!) {
        workflowStateUpdate(id: $id, input: $input) {
          success
        }
      }
    GQL

    STATE_ARCHIVE_MUTATION = <<~GQL
      mutation WorkflowStateArchive($id: String!) {
        workflowStateArchive(id: $id) {
          success
        }
      }
    GQL

    TAGS_QUERY = <<~GQL
      query Tags($teamId: String!, $after: String) {
        team(id: $teamId) {
          labels(first: 100, after: $after) {
            nodes {
              id
              name
              color
              team {
                id
              }
            }
            pageInfo {
              hasNextPage
              endCursor
            }
          }
        }
      }
    GQL

    TAG_CREATE_MUTATION = <<~GQL
      mutation IssueLabelCreate($input: IssueLabelCreateInput!) {
        issueLabelCreate(input: $input) {
          success
        }
      }
    GQL

    TAG_UPDATE_MUTATION = <<~GQL
      mutation IssueLabelUpdate($id: String!, $input: IssueLabelUpdateInput!) {
        issueLabelUpdate(id: $id, input: $input) {
          success
        }
      }
    GQL

    TAG_DELETE_MUTATION = <<~GQL
      mutation IssueLabelDelete($id: String!) {
        issueLabelDelete(id: $id) {
          success
        }
      }
    GQL

    GIT_AUTOMATION_STATES_QUERY = <<~GQL
      query GitAutomationStates($teamId: String!) {
        team(id: $teamId) {
          gitAutomationStates(first: 50) {
            nodes {
              id
              event
              state {
                name
              }
            }
          }
        }
      }
    GQL

    GIT_AUTOMATION_STATE_DELETE_MUTATION = <<~GQL
      mutation GitAutomationStateDelete($id: String!) {
        gitAutomationStateDelete(id: $id) {
          success
        }
      }
    GQL

    def workspace
      Settings.all.dig(:linear, :workspace)
    end

    def team
      Settings.all.dig(:linear, :team)
    end

    def headers
      { "Authorization" => ENV.fetch("LINEAR_TOKEN") }
    end

    def team_id
      @team_id ||= begin
        data = graphql(WORKSPACE_QUERY, { key: team })
        url_key = data.fetch(:organization).fetch(:urlKey)
        unless url_key == workspace
          raise "Linear workspace is #{url_key.inspect}, expected #{workspace.inspect}"
        end

        found = data.fetch(:teams).fetch(:nodes).find { |item| item.fetch(:key).to_s.casecmp?(team) }
        raise "Linear team #{team.inspect} not found" if found.blank?

        found.fetch(:id)
      end
    end

    def state_id(column)
      states.fetch(column)
    end

    def states
      @states ||= state_nodes.to_h { |state| [ column_key(state.fetch(:name)), state.fetch(:id) ] }
    end

    def states_by_id
      states.invert
    end

    def state_nodes
      graphql(STATES_QUERY, { teamId: team_id }).fetch(:team).fetch(:states).fetch(:nodes)
    end

    def tag_id(name)
      tags.fetch(name.to_s.downcase) { raise "Linear tag #{name.inspect} not found" }
    end

    def tags
      @tags ||= tag_nodes.to_h { |tag| [ tag.fetch(:name).downcase, tag.fetch(:id) ] }
    end

    def tag_nodes
      nodes = []
      after = nil
      loop do
        page = graphql(TAGS_QUERY, { teamId: team_id, after: }.compact).fetch(:team).fetch(:labels)
        nodes.concat(page.fetch(:nodes))
        break unless page.dig(:pageInfo, :hasNextPage)

        after = page.dig(:pageInfo, :endCursor)
        raise "Linear labels pagination cursor is missing" if after.blank?
      end
      nodes
    end

    def git_automation_nodes
      graphql(GIT_AUTOMATION_STATES_QUERY, { teamId: team_id })
        .fetch(:team)
        .fetch(:gitAutomationStates)
        .fetch(:nodes)
    end

    def sync_status_positions(states)
      floor = states.map { |state| state[:position].to_f }.max || -1000.0

      STATUSES.group_by { |status| status[:type] }.each_value do |wants|
        items = wants.filter_map do |want|
          states.find do |state|
            column_key(state[:name]) == column_key(want[:name]) && state[:type] == want[:type]
          end
        end
        next unless items.length == wants.length
        next if items.each_cons(2).all? { |left, right| left[:position].to_f < right[:position].to_f }

        items.each do |item|
          floor = next_position(floor)
          graphql(STATE_UPDATE_MUTATION, { id: item.fetch(:id), input: { position: floor } })
        end
      end
    end

    def next_position(floor)
      (((floor / 1000.0).floor + 1) * 1000).to_f
    end

    def match_state(current, want, used_ids)
      current.find do |state|
        !used_ids.include?(state.fetch(:id)) &&
          column_key(state[:name]) == column_key(want[:name]) &&
          state[:type] == want[:type]
      end || current.find do |state|
        !used_ids.include?(state.fetch(:id)) &&
          state[:type] == want[:type] &&
          STATUSES.none? { |status| column_key(status[:name]) == column_key(state[:name]) }
      end
    end

    def graphql(query, variables = {})
      response = Req.call(
        url: HOST,
        method: :post,
        headers:,
        payload: { query:, variables: },
      )
      errors = response[:errors]
      raise errors.first[:message] if errors.present?

      response.fetch(:data)
    end
  end
end

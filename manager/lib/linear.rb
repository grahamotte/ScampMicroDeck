class Linear
  HOST = "https://api.linear.app/graphql"
  STATUSES = [
    { name: "Backlog", type: "backlog", color: "#f2994a" },
    { name: "Planned", type: "unstarted", color: "#95a2b3" },
    { name: "Ready", type: "started", color: "#26b5ce" },
    { name: "Working", type: "started", color: "#f2c94c" },
    { name: "Review", type: "started", color: "#f2994a" },
    { name: "Approved", type: "started", color: "#4cb782" },
    { name: "Completed", type: "completed", color: "#5e6ad2" },
    { name: "Canceled", type: "canceled", color: "#95a2b3" },
  ].freeze
  TAGS = [
    { name: "working", color: "#f2c94c" },
    { name: "interactive", color: "#bb87fc" },
    { name: "variant: low", color: "#4cb782" },
    { name: "variant: medium", color: "#4cb782" },
    { name: "variant: high", color: "#4cb782" },
    { name: "variant: xhigh", color: "#4cb782" },
    { name: "model: xai/grok-4.6", color: "#26b5ce" },
  ].freeze

  class << self
    def reset
      @team_override = nil
      @team_id = nil
      @states = nil
      @tags = nil
      @users = nil
      @projects = nil
      @viewer = nil
    end

    def team_key
      team
    end

    def with_team(key)
      return yield if key.blank?

      previous = [ @team_override, @team_id, @states, @tags, @users, @projects, @viewer ]
      @team_override = key.to_s
      @team_id = nil
      @states = nil
      @tags = nil
      @users = nil
      @projects = nil
      @viewer = nil
      yield
    ensure
      if key.present?
        @team_override, @team_id, @states, @tags, @users, @projects, @viewer = previous
      end
    end

    def issues
      nodes = []
      after = nil
      loop do
        page = graphql(
          ISSUES_QUERY,
          { teamId: team_id, after: }.compact,
        ).fetch(:team).fetch(:issues)
        nodes.concat(page.fetch(:nodes))
        break unless page.dig(:pageInfo, :hasNextPage)

        after = page.dig(:pageInfo, :endCursor)
        break if after.blank?
      end
      nodes
    end

    def issue(identifier, allowed_team: nil)
      team_id
      found = graphql(ISSUE_QUERY, { id: identifier }).fetch(:issue)
      key = found.dig(:team, :key).to_s
      allowed = allowed_team == :any || key.casecmp?(team)
      unless allowed
        raise "Linear issue #{identifier} is in team #{key.inspect}, expected #{team.inspect}"
      end

      found
    end

    def create(title, body, column, parent: nil)
      graphql(
        ISSUE_CREATE_MUTATION,
        {
          input: {
            teamId: team_id,
            title:,
            description: body,
            stateId: state_id(column),
            parentId: parent,
          }.compact,
        },
      ).fetch(:issueCreate).fetch(:issue)
    end

    def comment(item, body, parent: nil)
      graphql(
        COMMENT_CREATE_MUTATION,
        { input: { issueId: item.fetch(:id), body:, parentId: parent }.compact },
      )
    end

    def comment_record(id)
      graphql(COMMENT_QUERY, { id: }).fetch(:comment)
    end

    def comment_update(id, body)
      graphql(COMMENT_UPDATE_MUTATION, { id:, input: { body: } })
    end

    def comment_delete(id)
      graphql(COMMENT_DELETE_MUTATION, { id: })
    end

    def link(item, url, title)
      attachments = item.dig(:attachments, :nodes) || []
      return false if attachments.any? { |attachment| attachment[:url] == url }

      graphql(ATTACHMENT_LINK_MUTATION, { issueId: item.fetch(:id), url:, title: }.compact)
      true
    rescue StandardError => error
      raise unless error.message.to_s.include?("Duplicate attachment")

      false
    end

    def unlink(item, url)
      attachments = item.dig(:attachments, :nodes) || []
      found = attachments.find { |attachment| attachment[:url] == url }
      raise "Link #{url.inspect} is not attached to #{identifier(item)}" if found.blank?

      graphql(ATTACHMENT_DELETE_MUTATION, { id: found.fetch(:id) })
    end

    def update(item, input)
      graphql(
        ISSUE_UPDATE_MUTATION,
        { id: item.fetch(:id), input: },
      ).fetch(:issueUpdate)
    end

    def list(column: nil, tag: nil, search: nil)
      issues.select do |item|
        next false if column.present? && self.column(item) != column.to_s.downcase
        next false if tag.present? && !tagged?(item, tag)
        if search.present?
          haystack = "#{identifier(item)} #{item[:title]}".downcase
          next false unless haystack.include?(search.to_s.downcase)
        end

        true
      end
    end

    def relate(item, type, other)
      other_item = issue(other, allowed_team: :any)
      from_id, to_id, relation_type = relation_input(item.fetch(:id), other_item.fetch(:id), type)
      graphql(
        ISSUE_RELATION_CREATE_MUTATION,
        { input: { issueId: from_id, relatedIssueId: to_id, type: relation_type } },
      )
    end

    def unrelate(item, other)
      other_item = issue(other, allowed_team: :any)
      found = find_relation(item, other_item.fetch(:id))
      if found.blank?
        raise "No relation between #{identifier(item)} and #{identifier(other_item)}"
      end

      graphql(ISSUE_RELATION_DELETE_MUTATION, { id: found.fetch(:id) })
    end

    def user_id(name)
      return viewer.fetch(:id) if name.to_s.downcase == "me"

      matches = user_nodes.select do |user|
        [ user[:name], user[:displayName], user[:email] ].compact.any? do |value|
          value.to_s.casecmp?(name.to_s)
        end
      end
      raise "Linear user #{name.inspect} not found" if matches.blank?
      raise "Linear user #{name.inspect} is ambiguous" if matches.size > 1

      matches.first.fetch(:id)
    end

    def project_id(name)
      found = project_nodes.find { |project| project[:name].to_s.casecmp?(name.to_s) }
      raise "Linear project #{name.inspect} not found" if found.blank?

      found.fetch(:id)
    end

    def viewer
      @viewer ||= graphql(VIEWER_QUERY).fetch(:viewer)
    end

    def normalize_description(text)
      text.to_s.gsub(/\[([^\]]+)\]\((?:https?:\/\/)?\1\/?\)/, '\1').gsub(/^( *)\* /, '\1- ')
    end

    def description_hash(text)
      Digest::SHA256.hexdigest(text.to_s)
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
      return state[:name].downcase if state.is_a?(Hash) && state[:name].present?
      return states_by_id[state] if state.present?

      nil
    end

    def identifier(item)
      item.fetch(:identifier)
    end

    def url(item)
      item.fetch(:url)
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
      live = []

      STATUSES.each do |want|
        existing = match_state(current, want, used_ids)
        if existing
          used_ids << existing.fetch(:id)
          input = {}
          input[:name] = want[:name] if existing[:name] != want[:name]
          input[:color] = want[:color] if existing[:color] != want[:color]
          if input.present?
            graphql(STATE_UPDATE_MUTATION, { id: existing.fetch(:id), input: })
            puts "renamed #{existing[:name]} to #{want[:name]}" if input[:name].present?
          end
          live << {
            id: existing.fetch(:id),
            name: want[:name],
            type: want[:type],
            position: existing[:position],
          }
        else
          previous = live.reverse.find { |item| item[:type] == want[:type] }
          position = previous.blank? ? 0.0 : previous[:position].to_f + 1.0
          graphql(
            STATE_CREATE_MUTATION,
            {
              input: {
                teamId: team_id,
                name: want[:name],
                type: want[:type],
                color: want[:color],
                position:,
              },
            },
          )
          puts "created #{want[:name]}"
          live << { name: want[:name], type: want[:type], position: }
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

      sync_status_positions(live)

      @states = nil
    end

    def sync_tags
      current = tag_nodes
      TAGS.each do |want|
        existing = current.find { |tag| tag[:name].to_s.downcase == want[:name].downcase }
        if existing
          next if existing[:color] == want[:color]

          graphql(TAG_UPDATE_MUTATION, { id: existing.fetch(:id), input: { color: want[:color] } })
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
      @tags = nil
    end

    def sync_git_automations
      git_automation_nodes.each do |rule|
        graphql(GIT_AUTOMATION_STATE_DELETE_MUTATION, { id: rule.fetch(:id) })
        puts "removed git automation #{rule.fetch(:event)} (#{rule.dig(:state, :name)})"
      end
    end

    private

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
              position
            }
          }
        }
      }
    GQL

    ISSUES_QUERY = <<~GQL
      query Issues($teamId: String!, $after: String) {
        team(id: $teamId) {
          issues(first: 100, after: $after) {
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

    ISSUE_QUERY = <<~GQL
      query Issue($id: String!) {
        issue(id: $id) {
          id
          identifier
          title
          url
          description
          priority
          estimate
          dueDate
          team {
            key
          }
          state {
            id
            name
          }
          assignee {
            id
            name
            displayName
          }
          project {
            id
            name
          }
          parent {
            identifier
            title
          }
          labels {
            nodes {
              id
              name
            }
          }
          children {
            nodes {
              identifier
              title
              state {
                name
              }
            }
          }
          attachments {
            nodes {
              id
              title
              url
            }
          }
          comments {
            nodes {
              id
              body
              createdAt
              parent {
                id
              }
              user {
                id
                name
              }
            }
          }
          relations {
            nodes {
              id
              type
              relatedIssue {
                id
                identifier
                title
              }
            }
          }
          inverseRelations {
            nodes {
              id
              type
              issue {
                id
                identifier
                title
              }
            }
          }
        }
      }
    GQL

    COMMENT_QUERY = <<~GQL
      query Comment($id: String!) {
        comment(id: $id) {
          id
          body
          user {
            id
            name
          }
          issue {
            identifier
            team {
              key
            }
          }
        }
      }
    GQL

    VIEWER_QUERY = <<~GQL
      query Viewer {
        viewer {
          id
          name
        }
      }
    GQL

    USERS_QUERY = <<~GQL
      query Users {
        users {
          nodes {
            id
            name
            displayName
            email
          }
        }
      }
    GQL

    PROJECTS_QUERY = <<~GQL
      query Projects($teamId: String!) {
        team(id: $teamId) {
          projects {
            nodes {
              id
              name
            }
          }
        }
      }
    GQL

    ISSUE_CREATE_MUTATION = <<~GQL
      mutation IssueCreate($input: IssueCreateInput!) {
        issueCreate(input: $input) {
          success
          issue {
            id
            identifier
            url
          }
        }
      }
    GQL

    COMMENT_CREATE_MUTATION = <<~GQL
      mutation CommentCreate($input: CommentCreateInput!) {
        commentCreate(input: $input) {
          success
        }
      }
    GQL

    ATTACHMENT_LINK_MUTATION = <<~GQL
      mutation AttachmentLinkURL($issueId: String!, $url: String!, $title: String) {
        attachmentLinkURL(issueId: $issueId, url: $url, title: $title) {
          success
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

    COMMENT_UPDATE_MUTATION = <<~GQL
      mutation CommentUpdate($id: String!, $input: CommentUpdateInput!) {
        commentUpdate(id: $id, input: $input) {
          success
        }
      }
    GQL

    COMMENT_DELETE_MUTATION = <<~GQL
      mutation CommentDelete($id: String!) {
        commentDelete(id: $id) {
          success
        }
      }
    GQL

    ATTACHMENT_DELETE_MUTATION = <<~GQL
      mutation AttachmentDelete($id: String!) {
        attachmentDelete(id: $id) {
          success
        }
      }
    GQL

    ISSUE_RELATION_CREATE_MUTATION = <<~GQL
      mutation IssueRelationCreate($input: IssueRelationCreateInput!) {
        issueRelationCreate(input: $input) {
          success
        }
      }
    GQL

    ISSUE_RELATION_DELETE_MUTATION = <<~GQL
      mutation IssueRelationDelete($id: String!) {
        issueRelationDelete(id: $id) {
          success
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
      query Tags($teamId: String!) {
        team(id: $teamId) {
          labels {
            nodes {
              id
              name
              color
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
      ENV.fetch("LINEAR_WORKSPACE")
    end

    def team
      @team_override.present? ? @team_override : ENV.fetch("LINEAR_TEAM")
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
      @states ||= state_nodes.to_h { |state| [ state.fetch(:name).downcase, state.fetch(:id) ] }
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
      graphql(TAGS_QUERY, { teamId: team_id }).fetch(:team).fetch(:labels).fetch(:nodes)
    end

    def git_automation_nodes
      graphql(GIT_AUTOMATION_STATES_QUERY, { teamId: team_id })
        .fetch(:team)
        .fetch(:gitAutomationStates)
        .fetch(:nodes)
    end

    def sync_status_positions(live)
      live.group_by { |item| item[:type] }.each_value do |items|
        ordered = items.sort_by { |item| item[:position].to_f }
        next if ordered.map { |item| item[:name] } == items.map { |item| item[:name] }

        items.each_with_index do |item, index|
          next if item[:id].blank?

          position = index.to_f
          next if item[:position].to_f == position

          graphql(STATE_UPDATE_MUTATION, { id: item[:id], input: { position: } })
        end
      end
    end

    def user_nodes
      @users ||= graphql(USERS_QUERY).fetch(:users).fetch(:nodes)
    end

    def project_nodes
      @projects ||= graphql(PROJECTS_QUERY, { teamId: team_id }).fetch(:team).fetch(:projects).fetch(:nodes)
    end

    def relation_input(from_id, to_id, type)
      case type.to_s.downcase.tr("_", "-")
      when "blocks"
        [ from_id, to_id, "blocks" ]
      when "blocked-by"
        [ to_id, from_id, "blocks" ]
      when "related"
        [ from_id, to_id, "related" ]
      when "duplicate"
        [ from_id, to_id, "duplicate" ]
      else
        raise "Unknown relation #{type.inspect}, expected one of blocks, blocked-by, related, duplicate"
      end
    end

    def find_relation(item, other_id)
      (item.dig(:relations, :nodes) || []).find { |rel| rel.dig(:relatedIssue, :id) == other_id } ||
        (item.dig(:inverseRelations, :nodes) || []).find { |rel| rel.dig(:issue, :id) == other_id }
    end

    def match_state(current, want, used_ids)
      current.find do |state|
        !used_ids.include?(state.fetch(:id)) &&
          state[:name].to_s.downcase == want[:name].downcase &&
          state[:type] == want[:type]
      end || current.find do |state|
        !used_ids.include?(state.fetch(:id)) &&
          state[:type] == want[:type] &&
          STATUSES.none? { |status| status[:name].downcase == state[:name].to_s.downcase }
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

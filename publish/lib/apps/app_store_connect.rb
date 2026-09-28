module Apps
  class AppStoreConnect
    BASE_URL = "https://api.appstoreconnect.apple.com"
    POLL_INTERVAL = 5
    POLL_TIMEOUT = 1_200
    CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    WAIT = -> { IO.select(nil, nil, nil, POLL_INTERVAL) }
    ACTIVE_SUBMISSION_STATES = %w[
      CANCELING
      COMPLETING
      IN_REVIEW
      WAITING_FOR_REVIEW
    ].freeze
    EDITABLE_VERSION_STATES = %w[
      DEVELOPER_REJECTED
      INVALID_BINARY
      METADATA_REJECTED
      PREPARE_FOR_SUBMISSION
      READY_FOR_REVIEW
      REJECTED
    ].freeze
    APPROVED_VERSION_STATES = %w[
      ACCEPTED
      DEVELOPER_REMOVED_FROM_SALE
      PENDING_APPLE_RELEASE
      PENDING_DEVELOPER_RELEASE
      PREORDER_READY_FOR_SALE
      PROCESSING_FOR_APP_STORE
      READY_FOR_DISTRIBUTION
      READY_FOR_SALE
      REMOVED_FROM_SALE
      REPLACED_WITH_NEW_VERSION
    ].freeze

    def initialize(
      clock: CLOCK,
      wait: WAIT
    )
      @clock = clock
      @wait = wait
    end

    def submit(target)
      return :skipped unless Apps.prepare_for_review?

      apps = get("/v1/apps", params: { "filter[bundleId]" => target.fetch(:bundleIdentifier) }).fetch(:data)
      raise "Expected one App Store app for #{target.fetch(:bundleIdentifier)}" unless apps.length == 1

      app = apps.fetch(0)
      version = store_version(app.fetch(:id), target)
      update_version(version.fetch(:id))
      localization = update_localization(version.fetch(:id))
      update_screenshots(localization.fetch(:id), target)
      update_review_details(version.fetch(:id))
      build = wait_for_processed_build(app.fetch(:id), target)

      patch(
        "/v1/appStoreVersions/#{version.fetch(:id)}/relationships/build",
        data: { type: "builds", id: build.fetch(:id) },
      )

      submission = prepare_submission(app.fetch(:id), version.fetch(:id), target.fetch(:platform))
      if target.fetch(:bundleIdentifier).include?("codemoto")
        puts "Skipping actual submission for #{target.fetch(:bundleIdentifier)}."
        return :prepared
      end
      return :prepared unless Apps.submit_for_review?

      finalize_submission(submission.fetch(:id))
      :submitted
    end

    def latest_approved_version(target)
      apps = get("/v1/apps", params: { "filter[bundleId]" => target.fetch(:bundleIdentifier) }).fetch(:data)
      raise "Expected one App Store app for #{target.fetch(:bundleIdentifier)}" unless apps.length == 1

      store_versions(apps.fetch(0).fetch(:id), target)
        .select { |version| APPROVED_VERSION_STATES.include?(version_state(version)) }
        .map { |version| version.dig(:attributes, :versionString) }
        .select(&:present?)
        .max_by { |version| Gem::Version.new(version) }
    end

    private

    def store_version(app_id, target)
      versions = store_versions(app_id, target)
      if versions.any? { |item| %w[IN_REVIEW WAITING_FOR_REVIEW].include?(version_state(item)) }
        cancel_active_submissions(app_id, target.fetch(:platform))
        versions = store_versions(app_id, target)
      end
      version = versions.find { |item| item.dig(:attributes, :versionString) == Apps.version } ||
        versions
          .select { |item| EDITABLE_VERSION_STATES.include?(version_state(item)) }
          .max_by { |item| item.dig(:attributes, :createdDate).to_s }
      @first_version = version.present? ? versions.one? : versions.blank?
      version || create_version(app_id, target)
    end

    def store_versions(app_id, target)
      get(
        "/v1/apps/#{app_id}/appStoreVersions",
        params: { "filter[platform]" => target.fetch(:platform), "limit" => 200 },
      ).fetch(:data)
    end

    def cancel_active_submissions(app_id, platform)
      submissions = get(
        "/v1/apps/#{app_id}/reviewSubmissions",
        params: { "filter[platform]" => platform, "limit" => 200 },
      ).fetch(:data).select { |item| ACTIVE_SUBMISSION_STATES.include?(item.dig(:attributes, :state)) }
      submissions.each do |submission|
        unless %w[CANCELING COMPLETING].include?(submission.dig(:attributes, :state))
          patch(
            "/v1/reviewSubmissions/#{submission.fetch(:id)}",
            data: {
              type: "reviewSubmissions",
              id: submission.fetch(:id),
              attributes: { canceled: true },
            },
          )
        end
        wait_for_submission_cancellation(submission.fetch(:id))
      end
    end

    def wait_for_submission_cancellation(submission_id)
      deadline = @clock.call + POLL_TIMEOUT
      loop do
        state = get("/v1/reviewSubmissions/#{submission_id}").dig(:data, :attributes, :state)
        return unless ACTIVE_SUBMISSION_STATES.include?(state)
        raise "Timed out waiting for review submission cancellation" if @clock.call >= deadline

        @wait.call
      end
    rescue Req::ResponseError => error
      return if error.status == 404

      raise
    end

    def create_version(app_id, target)
      post(
        "/v1/appStoreVersions",
        data: {
          type: "appStoreVersions",
          attributes: {
            platform: target.fetch(:platform),
            versionString: Apps.version,
            copyright: Apps.config.fetch(:copyright),
            releaseType: Apps.config.fetch(:releaseType),
          },
          relationships: {
            app: { data: { type: "apps", id: app_id } },
          },
        },
      ).fetch(:data)
    end

    def update_version(version_id)
      patch(
        "/v1/appStoreVersions/#{version_id}",
        data: {
          type: "appStoreVersions",
          id: version_id,
          attributes: Apps.config.slice(:copyright, :releaseType).merge(versionString: Apps.version),
        },
      )
    end

    def version_state(version)
      version.dig(:attributes, :appVersionState) || version.dig(:attributes, :appStoreState)
    end

    def update_localization(version_id)
      localizations = get("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations").fetch(:data)
      localization = localizations.find { |item| item.dig(:attributes, :locale) == Apps.config.fetch(:primaryLocale) }
      attributes = {
        description: Apps.config.fetch(:description),
        keywords: Apps.config.fetch(:keywords),
        marketingUrl: Apps.config.fetch(:marketingUrl),
        promotionalText: Apps.config.fetch(:promotionalText),
        supportUrl: Apps.config.fetch(:supportUrl),
      }
      attributes[:whatsNew] = Apps.config.fetch(:whatsNew) unless @first_version

      if localization.present?
        patch(
          "/v1/appStoreVersionLocalizations/#{localization.fetch(:id)}",
          data: {
            type: "appStoreVersionLocalizations",
            id: localization.fetch(:id),
            attributes:,
          },
        )
      else
        localization = post(
          "/v1/appStoreVersionLocalizations",
          data: {
            type: "appStoreVersionLocalizations",
            attributes: attributes.merge(locale: Apps.config.fetch(:primaryLocale)),
            relationships: {
              appStoreVersion: { data: { type: "appStoreVersions", id: version_id } },
            },
          },
        ).fetch(:data)
      end
      localization
    end

    def update_screenshots(localization_id, target)
      screenshots = target.fetch(:screenshots)
      sets = get(
        "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets",
        params: { "limit" => 200 },
      ).fetch(:data)
      processing = []

      screenshots.group_by { |screenshot| screenshot.fetch(:displayType) }.each do |display_type, configured|
        screenshot_set = sets.find { |item| item.dig(:attributes, :screenshotDisplayType) == display_type } ||
          create_screenshot_set(localization_id, display_type)
        existing = get("/v1/appScreenshotSets/#{screenshot_set.fetch(:id)}/appScreenshots").fetch(:data)
        names = configured.map { |screenshot| File.basename(Apps.screenshot_path(screenshot)) }
        existing.reject { |item| names.include?(item.dig(:attributes, :fileName)) }.each do |item|
          delete("/v1/appScreenshots/#{item.fetch(:id)}")
        end

        configured.each do |screenshot|
          path = Apps.screenshot_path(screenshot)
          checksum = Digest::MD5.file(path).hexdigest
          current = existing.find { |item| item.dig(:attributes, :fileName) == File.basename(path) }
          if current.present? && current.dig(:attributes, :sourceFileChecksum) == checksum
            processing << current.fetch(:id) if current.dig(:attributes, :assetDeliveryState, :state) != "COMPLETE"
            next
          end

          delete("/v1/appScreenshots/#{current.fetch(:id)}") if current.present?
          processing << upload_screenshot(screenshot_set.fetch(:id), path, checksum)
        end
      end
      wait_for_screenshots(processing)
    end

    def create_screenshot_set(localization_id, display_type)
      post(
        "/v1/appScreenshotSets",
        data: {
          type: "appScreenshotSets",
          attributes: { screenshotDisplayType: display_type },
          relationships: {
            appStoreVersionLocalization: {
              data: { type: "appStoreVersionLocalizations", id: localization_id },
            },
          },
        },
      ).fetch(:data)
    end

    def upload_screenshot(screenshot_set_id, path, checksum)
      data = post(
        "/v1/appScreenshots",
        data: {
          type: "appScreenshots",
          attributes: { fileName: File.basename(path), fileSize: File.size(path) },
          relationships: {
            appScreenshotSet: { data: { type: "appScreenshotSets", id: screenshot_set_id } },
          },
        },
      ).fetch(:data)
      file = File.binread(path)
      data.dig(:attributes, :uploadOperations).each do |operation|
        headers = operation.fetch(:requestHeaders).to_h do |header|
          [ header.fetch(:name), header.fetch(:value) ]
        end
        Req.call(
          url: operation.fetch(:url),
          method: operation.fetch(:method).downcase.to_sym,
          headers:,
          body: file.byteslice(operation.fetch(:offset), operation.fetch(:length)),
          content: :text,
        )
      end
      patch(
        "/v1/appScreenshots/#{data.fetch(:id)}",
        data: {
          type: "appScreenshots",
          id: data.fetch(:id),
          attributes: { uploaded: true, sourceFileChecksum: checksum },
        },
      )
      data.fetch(:id)
    end

    def wait_for_screenshots(ids)
      deadline = @clock.call + POLL_TIMEOUT
      while ids.present?
        ids = ids.reject do |id|
          state = get("/v1/appScreenshots/#{id}").dig(:data, :attributes, :assetDeliveryState, :state)
          raise "Screenshot #{id} failed processing" if state == "FAILED"

          state == "COMPLETE"
        end
        return if ids.blank?
        raise "Timed out waiting for screenshots to process" if @clock.call >= deadline

        @wait.call
      end
    end

    def update_review_details(version_id)
      attributes = review_attributes
      review_detail = get("/v1/appStoreVersions/#{version_id}/relationships/appStoreReviewDetail")[:data]

      if review_detail.present?
        patch(
          "/v1/appStoreReviewDetails/#{review_detail.fetch(:id)}",
          data: {
            type: "appStoreReviewDetails",
            id: review_detail.fetch(:id),
            attributes:,
          },
        )
      else
        review_detail = post(
          "/v1/appStoreReviewDetails",
          data: {
            type: "appStoreReviewDetails",
            attributes:,
            relationships: {
              appStoreVersion: { data: { type: "appStoreVersions", id: version_id } },
            },
          },
        ).fetch(:data)
      end
      update_review_attachments(review_detail.fetch(:id)) if Apps.config.fetch(:reviewAttachments, []).present?
    end

    def review_attributes
      attributes = Apps.config.slice(
        :contactEmail,
        :contactFirstName,
        :contactLastName,
        :contactPhone,
        :demoAccountName,
        :demoAccountPassword,
        :demoAccountRequired,
        :notes,
      )
      return attributes if attributes.fetch(:demoAccountRequired)

      attributes.except(:demoAccountName, :demoAccountPassword)
    end

    def update_review_attachments(review_detail_id)
      configured = Apps.config.fetch(:reviewAttachments)
      existing = get(
        "/v1/appStoreReviewDetails/#{review_detail_id}/appStoreReviewAttachments",
        params: { "limit" => 200 },
      ).fetch(:data)
      names = configured.map { |attachment| File.basename(Apps.review_attachment_path(attachment)) }
      existing.reject { |item| names.include?(item.dig(:attributes, :fileName)) }.each do |item|
        delete("/v1/appStoreReviewAttachments/#{item.fetch(:id)}")
      end
      processing = configured.filter_map do |attachment|
        path = Apps.review_attachment_path(attachment)
        checksum = Digest::MD5.file(path).hexdigest
        current = existing.find { |item| item.dig(:attributes, :fileName) == File.basename(path) }
        if current.present? && current.dig(:attributes, :sourceFileChecksum) == checksum
          next current.fetch(:id) if current.dig(:attributes, :assetDeliveryState, :state) != "COMPLETE"

          next
        end

        delete("/v1/appStoreReviewAttachments/#{current.fetch(:id)}") if current.present?
        upload_review_attachment(review_detail_id, path, checksum)
      end
      wait_for_review_attachments(processing)
    end

    def upload_review_attachment(review_detail_id, path, checksum)
      data = post(
        "/v1/appStoreReviewAttachments",
        data: {
          type: "appStoreReviewAttachments",
          attributes: { fileName: File.basename(path), fileSize: File.size(path) },
          relationships: {
            appStoreReviewDetail: { data: { type: "appStoreReviewDetails", id: review_detail_id } },
          },
        },
      ).fetch(:data)
      file = File.binread(path)
      data.dig(:attributes, :uploadOperations).each do |operation|
        headers = operation.fetch(:requestHeaders).to_h do |header|
          [ header.fetch(:name), header.fetch(:value) ]
        end
        Req.call(
          url: operation.fetch(:url),
          method: operation.fetch(:method).downcase.to_sym,
          headers:,
          body: file.byteslice(operation.fetch(:offset), operation.fetch(:length)),
          content: :text,
        )
      end
      patch(
        "/v1/appStoreReviewAttachments/#{data.fetch(:id)}",
        data: {
          type: "appStoreReviewAttachments",
          id: data.fetch(:id),
          attributes: { uploaded: true, sourceFileChecksum: checksum },
        },
      )
      data.fetch(:id)
    end

    def wait_for_review_attachments(ids)
      deadline = @clock.call + POLL_TIMEOUT
      while ids.present?
        ids = ids.reject do |id|
          state = get("/v1/appStoreReviewAttachments/#{id}").dig(:data, :attributes, :assetDeliveryState, :state)
          raise "Review attachment #{id} failed processing" if state == "FAILED"

          state == "COMPLETE"
        end
        return if ids.blank?
        raise "Timed out waiting for review attachments to process" if @clock.call >= deadline

        @wait.call
      end
    end

    def processed_build(app_id, target)
      response = get(
        "/v1/preReleaseVersions",
        params: {
          "filter[app]" => app_id,
          "filter[builds.version]" => Apps.build,
          "filter[platform]" => target.fetch(:platform),
          "filter[version]" => Apps.version,
          "include" => "builds",
          "limit" => 1,
          "limit[builds]" => 50,
        },
      )
      response.fetch(:included, []).find { |item| item.dig(:attributes, :processingState) == "VALID" }
    end

    def wait_for_processed_build(app_id, target)
      deadline = @clock.call + POLL_TIMEOUT
      loop do
        build = processed_build(app_id, target)
        return build if build.present?
        raise "Timed out waiting for build #{Apps.build} to process" if @clock.call >= deadline

        @wait.call
      end
    end

    def prepare_submission(app_id, version_id, platform)
      submissions = get(
        "/v1/apps/#{app_id}/reviewSubmissions",
        params: { "filter[platform]" => platform, "limit" => 200 },
      ).fetch(:data)
      items = submissions.to_h do |submission|
        [ submission.fetch(:id), get(
          "/v1/reviewSubmissions/#{submission.fetch(:id)}/items",
          params: { "include" => "appStoreVersion", "limit" => 50 },
        ).fetch(:data) ]
      end
      ready = submissions.select { |submission| submission.dig(:attributes, :state) == "READY_FOR_REVIEW" }
      current = ready.find do |submission|
        items.fetch(submission.fetch(:id)).any? do |item|
          item.dig(:relationships, :appStoreVersion, :data, :id) == version_id
        end
      end
      return current if current.present?

      draft = ready.fetch(0, nil)
      submissions.each do |submission|
        items.fetch(submission.fetch(:id)).each do |item|
          related = item.dig(:relationships, :appStoreVersion, :data)
          next if related.blank?
          next unless related.fetch(:id) == version_id || submission.fetch(:id) == draft&.fetch(:id)

          delete_if_present("/v1/reviewSubmissionItems/#{item.fetch(:id)}")
        end
      end
      return add_submission_item(draft, version_id) if draft.present?

      submission = post(
        "/v1/reviewSubmissions",
        data: {
          type: "reviewSubmissions",
          relationships: { app: { data: { type: "apps", id: app_id } } },
        },
      ).fetch(:data)
      add_submission_item(submission, version_id)
    end

    def add_submission_item(submission, version_id)
      post(
        "/v1/reviewSubmissionItems",
        data: {
          type: "reviewSubmissionItems",
          relationships: {
            appStoreVersion: { data: { type: "appStoreVersions", id: version_id } },
            reviewSubmission: { data: { type: "reviewSubmissions", id: submission.fetch(:id) } },
          },
        },
      )
      submission
    end

    def finalize_submission(submission_id)
      patch(
        "/v1/reviewSubmissions/#{submission_id}",
        data: {
          type: "reviewSubmissions",
          id: submission_id,
          attributes: { submitted: true },
        },
      )
    end

    def get(path, params: {})
      request(path, params:)
    end

    def post(path, data:)
      request(path, method: :post, payload: { data: })
    end

    def patch(path, data:)
      request(path, method: :patch, payload: { data: })
    end

    def delete(path)
      request(path, method: :delete)
    end

    def delete_if_present(path)
      delete(path)
    rescue Req::ResponseError => error
      return if error.status == 404

      raise
    end

    def request(path, method: :get, params: {}, payload: {})
      Req.call(
        url: "#{BASE_URL}#{path}",
        method:,
        params:,
        payload:,
        headers: { "Authorization" => "Bearer #{token}" },
      )
    end

    def token
      now = Time.now.to_i
      header = encode(alg: "ES256", kid: ENV.fetch("APPLE_KEY_ID"), typ: "JWT")
      payload = encode(
        iss: ENV.fetch("APPLE_ISSUER_ID"),
        iat: now,
        exp: now + 1_200,
        aud: "appstoreconnect-v1",
      )
      signature = Apps.private_key.sign(OpenSSL::Digest::SHA256.new, "#{header}.#{payload}")
      integers = OpenSSL::ASN1.decode(signature).value
      raw_signature = integers.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
      "#{header}.#{payload}.#{base64url(raw_signature)}"
    end

    def encode(value)
      base64url(JSON.generate(value))
    end

    def base64url(value)
      [ value ].pack("m0").tr("+/", "-_").delete("=")
    end
  end
end

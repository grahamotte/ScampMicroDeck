require_relative "../../test_helper"

class AppsAppStoreConnectTest < Minitest::Test
  def test_skips_app_store_changes_without_prepare
    Apps.prepare_for_review = false

    status = Apps::AppStoreConnect.new.submit(Apps.targets.fetch(0))

    assert_equal :skipped, status
  end

  def test_generates_signed_token
    token = Apps::AppStoreConnect.new.send(:token)
    header, payload, signature = token.split(".")

    assert_equal "ES256", decode(header).fetch("alg")
    assert_equal ENV.fetch("APPLE_ISSUER_ID"), decode(payload).fetch("iss")
    assert signature.present?
  end

  def test_times_out_waiting_for_processed_build
    times = [ 0, 0, 1_200 ]
    client = Apps::AppStoreConnect.new(clock: -> { times.shift })
    target = Apps.targets.fetch(0)
    Req.expects(:call).times(10).returns(
      { data: [ { id: "app" } ] },
      { data: [ { id: "version", attributes: { versionString: "1.2.3" } } ] },
      {},
      { data: [ { id: "localization", attributes: { locale: "en-US" } } ] },
      {},
      screenshot_sets,
      screenshots,
      { data: nil },
      { data: { id: "review" } },
      { included: [] },
    )

    error = assert_raises(RuntimeError) { client.submit(target) }

    assert_includes error.message, "Timed out waiting for build"
  end

  def test_waits_for_processed_build
    waits = 0
    client = Apps::AppStoreConnect.new(wait: -> { waits += 1 })
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/preReleaseVersions").twice.returns(
      { included: [] },
      { included: [ { id: "build", attributes: { processingState: "VALID" } } ] },
    )

    build = client.send(:wait_for_processed_build, "app", target)

    assert_equal "build", build.fetch(:id)
    assert_equal 1, waits
  end

  def test_finds_the_latest_approved_version
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/apps").returns(data: [ { id: "app" } ])
    expect_request(:get, "/v1/apps/app/appStoreVersions").returns(
      data: [
        { attributes: { appVersionState: "READY_FOR_SALE", versionString: "1.2.2" } },
        { attributes: { appVersionState: "READY_FOR_REVIEW", versionString: "1.4.0" } },
        { attributes: { appVersionState: "READY_FOR_DISTRIBUTION", versionString: "1.3.0" } },
      ],
    )

    version = Apps::AppStoreConnect.new.latest_approved_version(target)

    assert_equal "1.3.0", version
  end

  def test_returns_nil_without_an_approved_version
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/apps").returns(data: [ { id: "app" } ])
    expect_request(:get, "/v1/apps/app/appStoreVersions").returns(
      data: [ { attributes: { appVersionState: "READY_FOR_REVIEW", versionString: "1.2.3" } } ],
    )

    version = Apps::AppStoreConnect.new.latest_approved_version(target)

    assert_nil version
  end

  def test_prepares_without_submitting
    Apps.submit_for_review = false
    target = Apps.targets.fetch(0)
    requests = []
    Req.expects(:call).times(14).with { |request| requests << request }.returns(
      { data: [ { id: "app" } ] },
      { data: [ { id: "version", attributes: { versionString: "1.2.3" } } ] },
      {},
      { data: [ { id: "localization", attributes: { locale: "en-US" } } ] },
      {},
      screenshot_sets,
      screenshots,
      { data: nil },
      { data: { id: "review" } },
      { included: [ { id: "build", attributes: { processingState: "VALID" } } ] },
      {},
      { data: [ { id: "submission", attributes: { state: "READY_FOR_REVIEW" } } ] },
      { data: [] },
      {},
    )

    assert_equal :prepared, Apps::AppStoreConnect.new.submit(target)

    assert_request(requests, :post, "/v1/reviewSubmissionItems")
    refute requests.any? { |request|
      request[:payload].dig(:data, :attributes, :submitted) == true
    }
  end

  def test_prepares_codemoto_without_submitting
    target = Apps.targets.fetch(0).merge(bundleIdentifier: "com.grahamotte.codemoto")
    requests = []
    Req.expects(:call).times(14).with { |request| requests << request }.returns(
      { data: [ { id: "app" } ] },
      { data: [ { id: "version", attributes: { versionString: "1.2.3" } } ] },
      {},
      { data: [ { id: "localization", attributes: { locale: "en-US" } } ] },
      {},
      screenshot_sets,
      screenshots,
      { data: nil },
      { data: { id: "review" } },
      { included: [ { id: "build", attributes: { processingState: "VALID" } } ] },
      {},
      { data: [ { id: "submission", attributes: { state: "READY_FOR_REVIEW" } } ] },
      { data: [] },
      {},
    )

    output, = capture_io do
      assert_equal :prepared, Apps::AppStoreConnect.new.submit(target)
    end

    assert_includes output, "Skipping actual submission"
    assert_request(requests, :patch, "/v1/appStoreVersions/version") do |attributes|
      assert_equal "1.2.3", attributes.fetch(:versionString)
      assert_equal "2026 Example", attributes.fetch(:copyright)
      assert_equal "AFTER_APPROVAL", attributes.fetch(:releaseType)
    end
    assert_request(requests, :patch, "/v1/appStoreVersionLocalizations/localization") do |attributes|
      assert_equal "Promotional text", attributes.fetch(:promotionalText)
      assert_equal "https://example.com/support", attributes.fetch(:supportUrl)
      refute attributes.key?(:whatsNew)
    end
    assert_request(requests, :post, "/v1/appStoreReviewDetails") do |attributes|
      assert_equal "login", attributes.fetch(:demoAccountName)
      assert_equal "First", attributes.fetch(:contactFirstName)
      assert_equal "Notes", attributes.fetch(:notes)
    end
    assert_request(requests, :post, "/v1/reviewSubmissionItems")
    refute requests.any? { |request|
      request[:payload].dig(:data, :attributes, :submitted) == true
    }
  end

  def test_creates_version_with_release_settings
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/apps/app/appStoreVersions").returns(data: [])
    request = nil
    Req.expects(:call).with do |item|
      request = item
      item[:method] == :post && item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appStoreVersions"
    end.returns(data: { id: "version" })

    version = Apps::AppStoreConnect.new.send(:store_version, "app", target)

    assert_equal "version", version.fetch(:id)
    assert_equal "1.2.3", request.dig(:payload, :data, :attributes, :versionString)
    assert_equal "2026 Example", request.dig(:payload, :data, :attributes, :copyright)
    assert_equal "AFTER_APPROVAL", request.dig(:payload, :data, :attributes, :releaseType)
  end

  def test_reuses_a_version_ready_for_review
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/apps/app/appStoreVersions").returns(
      data: [
        {
          id: "draft",
          attributes: {
            appVersionState: "READY_FOR_REVIEW",
            createdDate: "2026-01-01",
            versionString: "1.2.2",
          },
        },
      ],
    )

    version = Apps::AppStoreConnect.new.send(:store_version, "app", target)

    assert_equal "draft", version.fetch(:id)
  end

  def test_cancels_an_in_review_submission_and_reuses_its_version
    target = Apps.targets.fetch(0)
    Req.expects(:call).twice.with do |item|
      item[:method] == :get &&
        item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/apps/app/appStoreVersions"
    end.returns(
      data: [ { id: "version", attributes: { appVersionState: "IN_REVIEW", versionString: "1.2.2" } } ],
    ).then.returns(
      data: [ { id: "version", attributes: { appVersionState: "DEVELOPER_REJECTED", versionString: "1.2.2" } } ],
    )
    expect_request(:get, "/v1/apps/app/reviewSubmissions").returns(
      data: [ { id: "submission", attributes: { state: "IN_REVIEW" } } ],
    )
    Req.expects(:call).with do |item|
      item[:method] == :patch &&
        item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/reviewSubmissions/submission" &&
        item.dig(:payload, :data, :attributes, :canceled)
    end.returns({})
    expect_request(:get, "/v1/reviewSubmissions/submission").returns(
      data: { attributes: { state: "CANCELED" } },
    )

    version = Apps::AppStoreConnect.new.send(:store_version, "app", target)

    assert_equal "version", version.fetch(:id)
  end

  def test_treats_a_missing_canceled_submission_as_complete
    error = Req::ResponseError.new("Submission cannot be found", status: 404)
    expect_request(:get, "/v1/reviewSubmissions/submission").raises(error)

    result = Apps::AppStoreConnect.new.send(:wait_for_submission_cancellation, "submission")

    assert_nil result
  end

  def test_sends_whats_new_for_subsequent_versions
    client = Apps::AppStoreConnect.new
    target = Apps.targets.fetch(0)
    expect_request(:get, "/v1/apps/app/appStoreVersions").returns(
      data: [
        { id: "version", attributes: { versionString: "1.2.3" } },
        { id: "previous", attributes: { versionString: "1.2.2" } },
      ],
    )
    expect_request(:get, "/v1/appStoreVersions/version/appStoreVersionLocalizations").returns(
      data: [ { id: "localization", attributes: { locale: "en-US" } } ],
    )
    request = nil
    Req.expects(:call).with do |item|
      request = item
      item[:method] == :patch &&
        item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appStoreVersionLocalizations/localization"
    end.returns({})

    version = client.send(:store_version, "app", target)
    client.send(:update_localization, version.fetch(:id))

    assert_equal "Changes", request.dig(:payload, :data, :attributes, :whatsNew)
  end

  def test_omits_demo_credentials_when_not_required
    Apps.config[:demoAccountRequired] = false

    attributes = Apps::AppStoreConnect.new.send(:review_attributes)

    assert_equal false, attributes.fetch(:demoAccountRequired)
    refute attributes.key?(:demoAccountName)
    refute attributes.key?(:demoAccountPassword)
  end

  def test_uploads_missing_review_attachment
    client = Apps::AppStoreConnect.new
    path = configure_review_attachments
    checksum = Digest::MD5.file(path).hexdigest
    expect_request(:get, "/v1/appStoreReviewDetails/review/appStoreReviewAttachments").returns(data: [])
    request = nil
    Req.expects(:call).with do |item|
      matches = item[:method] == :post &&
        item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appStoreReviewAttachments"
      request = item if matches
      matches
    end.returns(
      data: {
        id: "attachment",
        attributes: {
          uploadOperations: [
            {
              length: File.size(path),
              method: "PUT",
              offset: 0,
              requestHeaders: [ { name: "Content-Type", value: "application/zip" } ],
              url: "https://upload.example.com/attachment",
            },
          ],
        },
      },
    )
    Req.expects(:call).with do |item|
      item[:url] == "https://upload.example.com/attachment" &&
        item[:method] == :put &&
        item[:headers] == { "Content-Type" => "application/zip" } &&
        item[:body] == File.binread(path)
    end.returns("")
    Req.expects(:call).with do |item|
      item[:method] == :patch &&
        item[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appStoreReviewAttachments/attachment" &&
        item.dig(:payload, :data, :attributes) == { uploaded: true, sourceFileChecksum: checksum }
    end.returns({})
    expect_request(:get, "/v1/appStoreReviewAttachments/attachment").returns(
      data: { attributes: { assetDeliveryState: { state: "COMPLETE" } } },
    )

    client.send(:update_review_attachments, "review")

    assert_equal File.basename(path), request.dig(:payload, :data, :attributes, :fileName)
    assert_equal File.size(path), request.dig(:payload, :data, :attributes, :fileSize)
    assert_equal "review", request.dig(
      :payload,
      :data,
      :relationships,
      :appStoreReviewDetail,
      :data,
      :id,
    )
  end

  def test_reuses_unchanged_review_attachment_and_removes_unconfigured_attachments
    path = configure_review_attachments
    expect_request(:get, "/v1/appStoreReviewDetails/review/appStoreReviewAttachments").returns(
      data: [
        {
          id: "attachment",
          attributes: {
            assetDeliveryState: { state: "COMPLETE" },
            fileName: File.basename(path),
            sourceFileChecksum: Digest::MD5.file(path).hexdigest,
          },
        },
        {
          id: "obsolete",
          attributes: { fileName: "obsolete.zip" },
        },
      ],
    )
    expect_request(:delete, "/v1/appStoreReviewAttachments/obsolete").returns({})

    Apps::AppStoreConnect.new.send(:update_review_attachments, "review")
  end

  def test_waits_for_review_attachment_processing
    waits = 0
    client = Apps::AppStoreConnect.new(wait: -> { waits += 1 })
    expect_request(:get, "/v1/appStoreReviewAttachments/attachment").twice.returns(
      { data: { attributes: { assetDeliveryState: { state: "UPLOAD_COMPLETE" } } } },
      { data: { attributes: { assetDeliveryState: { state: "COMPLETE" } } } },
    )

    client.send(:wait_for_review_attachments, [ "attachment" ])

    assert_equal 1, waits
  end

  def test_rejects_failed_review_attachment_processing
    client = Apps::AppStoreConnect.new
    expect_request(:get, "/v1/appStoreReviewAttachments/attachment").returns(
      data: { attributes: { assetDeliveryState: { state: "FAILED" } } },
    )

    error = assert_raises(RuntimeError) do
      client.send(:wait_for_review_attachments, [ "attachment" ])
    end

    assert_includes error.message, "failed processing"
  end

  def test_times_out_review_attachment_processing
    times = [ 0, 1_200 ]
    client = Apps::AppStoreConnect.new(clock: -> { times.shift })
    expect_request(:get, "/v1/appStoreReviewAttachments/attachment").returns(
      data: { attributes: { assetDeliveryState: { state: "UPLOAD_COMPLETE" } } },
    )

    error = assert_raises(RuntimeError) do
      client.send(:wait_for_review_attachments, [ "attachment" ])
    end

    assert_includes error.message, "Timed out"
  end

  def test_uploads_missing_screenshot
    client = Apps::AppStoreConnect.new
    target = Apps.targets.fetch(0)
    screenshot = target.fetch(:screenshots).fetch(0)
    path = Apps.screenshot_path(screenshot)
    checksum = Digest::MD5.file(path).hexdigest
    expect_request(:get, "/v1/appStoreVersionLocalizations/localization/appScreenshotSets").returns(data: [])
    expect_request(:post, "/v1/appScreenshotSets").returns(data: { id: "set" })
    expect_request(:get, "/v1/appScreenshotSets/set/appScreenshots").returns(data: [])
    expect_request(:post, "/v1/appScreenshots").returns(
      data: {
        id: "screenshot",
        attributes: {
          uploadOperations: [
            {
              length: File.size(path),
              method: "PUT",
              offset: 0,
              requestHeaders: [ { name: "Content-Type", value: "image/jpeg" } ],
              url: "https://upload.example.com/screenshot",
            },
          ],
        },
      },
    )
    Req.expects(:call).with do |request|
      request[:url] == "https://upload.example.com/screenshot" &&
        request[:method] == :put &&
        request[:headers] == { "Content-Type" => "image/jpeg" } &&
        request[:body] == File.binread(path)
    end.returns("")
    Req.expects(:call).with do |request|
      request[:method] == :patch &&
        request[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appScreenshots/screenshot" &&
        request.dig(:payload, :data, :attributes, :sourceFileChecksum) == checksum
    end.returns({})
    expect_request(:get, "/v1/appScreenshots/screenshot").returns(
      data: { attributes: { assetDeliveryState: { state: "COMPLETE" } } },
    )

    client.send(:update_screenshots, "localization", target)
  end

  def test_does_not_reupload_unchanged_screenshot
    target = Apps.targets.fetch(0)
    Req.expects(:call).twice.returns(screenshot_sets, screenshots)

    Apps::AppStoreConnect.new.send(:update_screenshots, "localization", target)
  end

  def test_waits_for_screenshot_processing
    waits = 0
    client = Apps::AppStoreConnect.new(wait: -> { waits += 1 })
    Req.expects(:call).twice.with do |request|
      request[:method] == :get &&
        request[:url] == "#{Apps::AppStoreConnect::BASE_URL}/v1/appScreenshots/screenshot"
    end.returns(
      { data: { attributes: { assetDeliveryState: { state: "UPLOAD_COMPLETE" } } } },
      { data: { attributes: { assetDeliveryState: { state: "COMPLETE" } } } },
    )

    client.send(:wait_for_screenshots, [ "screenshot" ])

    assert_equal 1, waits
  end

  def test_rejects_failed_screenshot_processing
    client = Apps::AppStoreConnect.new
    expect_request(:get, "/v1/appScreenshots/screenshot").returns(
      data: { attributes: { assetDeliveryState: { state: "FAILED" } } },
    )

    error = assert_raises(RuntimeError) do
      client.send(:wait_for_screenshots, [ "screenshot" ])
    end

    assert_includes error.message, "failed processing"
  end

  def test_times_out_screenshot_processing
    times = [ 0, 1_200 ]
    client = Apps::AppStoreConnect.new(clock: -> { times.shift })
    expect_request(:get, "/v1/appScreenshots/screenshot").returns(
      data: { attributes: { assetDeliveryState: { state: "UPLOAD_COMPLETE" } } },
    )

    error = assert_raises(RuntimeError) do
      client.send(:wait_for_screenshots, [ "screenshot" ])
    end

    assert_includes error.message, "Timed out"
  end

  def test_reuses_submission_containing_version
    expect_request(:get, "/v1/apps/app/reviewSubmissions").returns(
      data: [ { id: "submission", attributes: { state: "READY_FOR_REVIEW" } } ],
    )
    expect_request(:get, "/v1/reviewSubmissions/submission/items").returns(
      data: [
        {
          relationships: {
            appStoreVersion: { data: { id: "version", type: "appStoreVersions" } },
          },
        },
      ],
    )

    submission = Apps::AppStoreConnect.new.send(:prepare_submission, "app", "version", "IOS")

    assert_equal "submission", submission.fetch(:id)
  end

  def test_replaces_version_in_existing_submission
    expect_request(:get, "/v1/apps/app/reviewSubmissions").returns(
      data: [ { id: "occupied", attributes: { state: "READY_FOR_REVIEW" } } ],
    )
    expect_request(:get, "/v1/reviewSubmissions/occupied/items").returns(
      data: [
        {
          id: "item",
          relationships: {
            appStoreVersion: { data: { id: "other", type: "appStoreVersions" } },
          },
        },
      ],
    )
    expect_request(:delete, "/v1/reviewSubmissionItems/item").returns({})
    expect_request(:post, "/v1/reviewSubmissionItems").returns({})

    submission = Apps::AppStoreConnect.new.send(:prepare_submission, "app", "version", "MAC_OS")

    assert_equal "occupied", submission.fetch(:id)
  end

  def test_ignores_a_missing_item_while_detaching_version_from_stale_submission
    expect_request(:get, "/v1/apps/app/reviewSubmissions").returns(
      data: [
        { id: "stale", attributes: { state: "CANCELED" } },
        { id: "draft", attributes: { state: "READY_FOR_REVIEW" } },
      ],
    )
    expect_request(:get, "/v1/reviewSubmissions/stale/items").returns(
      data: [
        {
          id: "stale-item",
          relationships: { appStoreVersion: { data: { id: "version", type: "appStoreVersions" } } },
        },
      ],
    )
    expect_request(:get, "/v1/reviewSubmissions/draft/items").returns(data: [])
    error = Req::ResponseError.new("Submission item cannot be found", status: 404)
    expect_request(:delete, "/v1/reviewSubmissionItems/stale-item").raises(error)
    expect_request(:post, "/v1/reviewSubmissionItems").returns({})

    submission = Apps::AppStoreConnect.new.send(:prepare_submission, "app", "version", "IOS")

    assert_equal "draft", submission.fetch(:id)
  end

  private

  def decode(value)
    padding = "=" * ((4 - value.length % 4) % 4)
    JSON.parse("#{value}#{padding}".tr("-_", "+/").unpack1("m0"))
  end

  def expect_request(method, path)
    Req.expects(:call).with do |request|
      request[:method] == method && request[:url] == "#{Apps::AppStoreConnect::BASE_URL}#{path}"
    end
  end

  def assert_request(requests, method, path)
    request = requests.find do |item|
      item[:method] == method && item[:url] == "#{Apps::AppStoreConnect::BASE_URL}#{path}"
    end
    assert request, "Missing #{method.upcase} #{path}"
    yield request.dig(:payload, :data, :attributes) if block_given?
  end

  def screenshot_sets
    {
      data: [ { id: "set", attributes: { screenshotDisplayType: "APP_IPHONE_65" } } ],
    }
  end

  def screenshots
    screenshot = Apps.targets.fetch(0).fetch(:screenshots).fetch(0)
    path = Apps.screenshot_path(screenshot)
    {
      data: [
        {
          id: "screenshot",
          attributes: {
            assetDeliveryState: { state: "COMPLETE" },
            fileName: File.basename(path),
            sourceFileChecksum: Digest::MD5.file(path).hexdigest,
          },
        },
      ],
    }
  end

  def configure_review_attachments
    path = File.join(Apps.root, "review", "sample.zip")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "attachment")
    Apps.config[:reviewAttachments] = [ { path: } ]
    path
  end
end

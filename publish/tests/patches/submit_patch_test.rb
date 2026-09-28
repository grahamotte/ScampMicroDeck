require_relative "../test_helper"

class AppsSubmitPatchTest < Minitest::Test
  def test_skips_app_store_submission
    Apps.config[:skip_app_stores] = true

    refute Apps::SubmitPatch.needed?
    Apps::SubmitPatch.call
  end

  def test_updates_metadata_and_submission_every_time
    stub_submission_requests
    stub_submission_requests

    Apps::SubmitPatch.apply
    Apps::SubmitPatch.apply

    assert Apps::SubmitPatch.needed?
    assert_equal "submitted", Cache.get("apps/1.2.3/ios/submission")
  end

  def test_resubmits_after_canceling_an_active_submission
    Cache.set("apps/1.2.3/ios/submission", "submitted")
    stub_submission_requests(active: true)

    Apps::SubmitPatch.apply

    assert_equal "submitted", Cache.get("apps/1.2.3/ios/submission")
  end

  def test_skips_submission_preparation_without_prepare
    Apps.prepare_for_review = false

    refute Apps::SubmitPatch.needed?
    Apps::SubmitPatch.call

    assert_nil Cache.get("apps/1.2.3/ios/submission")
  end

  def test_prepares_submission_without_submitting
    Apps.submit_for_review = false
    stub_submission_requests(submit: false)

    Apps::SubmitPatch.apply

    assert Apps::SubmitPatch.needed?
    assert_equal "prepared", Cache.get("apps/1.2.3/ios/submission")
  end

  private

  def stub_submission_requests(active: false, submit: true)
    expect_request(:get, "/v1/apps").returns(data: [ { id: "app" } ])
    if active
      expect_request(:get, "/v1/apps/app/appStoreVersions").twice.returns(
        data: [
          {
            id: "version",
            attributes: { appVersionState: "WAITING_FOR_REVIEW", versionString: "1.2.3" },
          },
        ],
      ).then.returns(
        data: [
          {
            id: "version",
            attributes: { appVersionState: "DEVELOPER_REJECTED", versionString: "1.2.3" },
          },
        ],
      )
      expect_request(:get, "/v1/apps/app/reviewSubmissions").twice.returns(
        data: [ { id: "active", attributes: { state: "WAITING_FOR_REVIEW" } } ],
      ).then.returns(
        data: [ { id: "submission", attributes: { state: "READY_FOR_REVIEW" } } ],
      )
      expect_request(:patch, "/v1/reviewSubmissions/active").returns({})
      expect_request(:get, "/v1/reviewSubmissions/active").returns(
        data: { attributes: { state: "CANCELED" } },
      )
    else
      expect_request(:get, "/v1/apps/app/appStoreVersions").returns(
        data: [ { id: "version", attributes: { versionString: "1.2.3" } } ],
      )
    end
    expect_request(:patch, "/v1/appStoreVersions/version").returns({})
    expect_request(:get, "/v1/appStoreVersions/version/appStoreVersionLocalizations").returns(
      data: [ { id: "localization", attributes: { locale: "en-US" } } ],
    )
    expect_request(:patch, "/v1/appStoreVersionLocalizations/localization").returns({})
    expect_request(:get, "/v1/appStoreVersionLocalizations/localization/appScreenshotSets").returns(
      data: [ { id: "set", attributes: { screenshotDisplayType: "APP_IPHONE_65" } } ],
    )
    screenshot = Apps.targets.fetch(0).fetch(:screenshots).fetch(0)
    path = Apps.screenshot_path(screenshot)
    expect_request(:get, "/v1/appScreenshotSets/set/appScreenshots").returns(
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
    )
    expect_request(:get, "/v1/appStoreVersions/version/relationships/appStoreReviewDetail").returns(
      data: { id: "review" },
    )
    expect_request(:patch, "/v1/appStoreReviewDetails/review").returns({})
    expect_request(:get, "/v1/preReleaseVersions").returns(
      included: [ { id: "build", attributes: { processingState: "VALID" } } ],
    )
    expect_request(:patch, "/v1/appStoreVersions/version/relationships/build").returns({})

    unless active
      expect_request(:get, "/v1/apps/app/reviewSubmissions").returns(
        data: [ { id: "submission", attributes: { state: "READY_FOR_REVIEW" } } ],
      )
    end
    expect_request(:get, "/v1/reviewSubmissions/submission/items").returns(data: [])
    expect_request(:post, "/v1/reviewSubmissionItems").returns({})
    expect_request(:patch, "/v1/reviewSubmissions/submission").returns({}) if submit
  end

  def expect_request(method, path)
    Req.expects(:call).with do |request|
      request[:method] == method && request[:url] == "#{Apps::AppStoreConnect::BASE_URL}#{path}"
    end
  end
end

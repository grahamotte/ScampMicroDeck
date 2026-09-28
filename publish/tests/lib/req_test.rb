require_relative "../test_helper"

class ReqTest < Minitest::Test
  def test_json_request
    stub_request(:post, "https://example.com/items?page=2")
      .with(body: '{"item":"value"}', headers: { "Content-Type" => "application/json" })
      .to_return(body: '{"item_id":3}')
    result = nil

    output, = capture_io do
      result = PublishTestMethods::REQ_CALL.call(
        url: "https://example.com/items",
        method: :post,
        params: { page: 2 },
        payload: { item: "value" },
      )
    end

    assert_equal({ item_id: 3 }, result)
    assert_includes output, "POST https://example.com/items"
  end

  def test_text_response
    stub_request(:get, "https://example.com/text").to_return(body: "content")
    result = nil

    capture_io { result = PublishTestMethods::REQ_CALL.call(url: "https://example.com/text", content: :text) }

    assert_equal "content", result
  end

  def test_reports_api_error_details
    stub_request(:post, "https://example.com/items")
      .to_return(
        status: 409,
        body: JSON.generate(
          errors: [
            {
              detail: "Resource cannot be reviewed",
              meta: {
                associatedErrors: [
                  { detail: "Missing screenshot" },
                  { title: "Missing age rating" },
                ],
              },
            },
          ],
        ),
      )

    error = assert_raises(Req::ResponseError) do
      capture_io { PublishTestMethods::REQ_CALL.call(url: "https://example.com/items", method: :post) }
    end

    assert_equal 409, error.status
    assert_equal(
      "POST https://example.com/items failed (409): Resource cannot be reviewed; Missing screenshot; Missing age rating",
      error.message,
    )
    assert_nil error.cause
  end
end

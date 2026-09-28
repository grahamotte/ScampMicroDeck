require_relative "lib/require"

mode = ARGV.first
raise "Unknown publish mode: #{mode}" unless [ nil, "stop_before_prepare", "stop_before_submit" ].include?(mode)

Apps.prepare_for_review = false if mode == "stop_before_prepare"
Apps.submit_for_review = false if mode.present?

Apps::ValidationPatch.call
Apps::BuildPatch.call
Apps::RevisionPatch.call
Apps::UploadPatch.call
Apps::SubmitPatch.call

module Apps
  class SubmitPatch < BasePatch
    class << self
      def needed? = !Apps.skip_app_stores? && Apps.prepare_for_review?

      def apply
        client = AppStoreConnect.new
        Apps.targets.each do |target|
          puts "Preparing #{target.fetch(:name)} submission..."
          status = client.submit(target)
          Cache.set(cache_key(target), status)
        end
      end

      private

      def cache_key(target)
        "apps/#{Apps.version}/#{target.fetch(:name)}/submission"
      end
    end
  end
end

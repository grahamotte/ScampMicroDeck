class InstanceDestroyPatch < BasePatch
  class << self
    def always
      worker_records, records = Cloudflare.current_dns_records.partition { |x| x.dig(:meta, :origin_worker_id).present? }
      worker_records.map { |x| x.dig(:meta, :origin_worker_id) }.uniq.each do |domain_id|
        Cloudflare.delete_worker_domain(domain_id)
      end
      records.each do |record|
        Cloudflare.delete_dns_record(record[:id])
      end
      Cloudflare.delete_worker(Sources::Website.worker_name)
      Instance.destroy
    end
  end
end

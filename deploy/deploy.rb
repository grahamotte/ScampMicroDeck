require_relative "lib/require"

if Subdomains.droplet?
  InstanceCreatePatch.call
  DeployUserPatch.call
  SwapPatch.call
  HistoryPatch.call
  UpdatePatch.call
  GitDeploymentPatch.call
  DependenciesPatch.call
  DnsPatch.call
  CertPatch.call
  SecretsPatch.call
  PostgresPatch.call
  NginxPatch.call
  AppPatch.call
end

MailDnsPatch.call
RedirectPatch.call
WebsitePatch.call

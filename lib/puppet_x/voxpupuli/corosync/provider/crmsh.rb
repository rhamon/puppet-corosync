begin
  require 'puppet_x/voxpupuli/corosync/provider'
  require 'puppet_x/voxpupuli/corosync/provider/cib_helper'
rescue LoadError
  require 'pathname' # WORKAROUND #14073, #7788 and SERVER-973
  corosync = Puppet::Module.find('corosync', Puppet[:environment].to_s)
  raise(LoadError, "Unable to find corosync module in modulepath #{Puppet[:basemodulepath] || Puppet[:modulepath]}") unless corosync
  require File.join corosync.path, 'lib/puppet_x/voxpupuli/corosync/provider'
  require File.join corosync.path, 'lib/puppet_x/voxpupuli/corosync/provider/cib_helper'
end

class PuppetX::Voxpupuli::Corosync::Provider::Crmsh < PuppetX::Voxpupuli::Corosync::Provider::CibHelper
  # Yep, that's right we are parsing XML...FUN! (It really wasn't that bad)
  require 'rexml/document'

  initvars
  commands crm_attribute: 'crm_attribute'
  commands crm: 'crm'

  # Corosync takes a while to build the initial CIB configuration once the
  # service is started for the first time.  This provides us a way to wait
  # until we're up so we can make changes that don't disappear in to a black
  # hole.
  # rubocop:disable Style/ClassVars
  @@crmready = nil
  # rubocop:enable Style/ClassVars
  def self.ready?
    return true if @@crmready
    cmd =  [command(:crm_attribute), '--type', 'crm_config', '--query', '--name', 'dc-version']
    raw, status = run_command_in_cib(cmd, nil, false)
    if status == 0
      # rubocop:disable Style/ClassVars
      @@crmready = true
      # rubocop:enable Style/ClassVars
      # Sleeping a spare two since it seems that dc-version is returning before
      # It is really ready to take config changes, but it is close enough.
      # Probably need to find a better way to check for readiness.
      sleep 2
      return true
    else
      debug("Corosync not ready, retrying: #{raw}")
      return false
    end
  end

  def self.block_until_ready(timeout = 120)
    Timeout.timeout(timeout) do
      sleep 2 until ready?
    end
  end

  def self.prefetch(resources)
    instances.each do |prov|
      # rubocop:disable Lint/AssignmentInCondition
      if res = resources[prov.name.to_s]
        # rubocop:enable Lint/AssignmentInCondition
        res.provider = prov
      end
    end
  end

  def exists?
    self.class.block_until_ready
    debug(@property_hash.inspect)
    !(@property_hash[:ensure] == :absent || @property_hash.empty?)
  end
end

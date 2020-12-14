require 'shellwords'

require_relative "../../util/unix_mount_helpers"

module VagrantPlugins
  module Parallels
    module GuestLinuxCap
      class MountParallelsSharedFolder
        extend VagrantPlugins::Parallels::Util::UnixMountHelpers

        # Mounts Parallels Desktop shared folder on linux guest
        #
        # @param [Machine] machine
        # @param [String] name of mount
        # @param [String] path of mount on guest
        # @param [Hash] hash of mount options
        def self.mount_parallels_shared_folder(machine, name, guestpath, options)
          # Sanity check for mount options: we are not supporting
          # VirtualBox-specific 'fmode' and 'dmode' options
          if options[:mount_options]
            invalid_opts = options[:mount_options].select do |opt|
              opt =~ /^(d|f)mode/
            end

            if !invalid_opts.empty?
              raise Errors::LinuxPrlFsInvalidOptions, options: invalid_opts
            end
          end

          guest_path = Shellwords.escape(guestpath)
          mount_type = options[:plugin].capability(:mount_type)

          @@logger.debug("Mounting #{name} (#{options[:hostpath]} to #{guestpath})")

          mount_options, mount_uid, mount_gid = options[:plugin].capability(:mount_options, name, guest_path, options)
          mount_command = "mount -t #{mount_type} -o #{mount_options} #{name} #{guest_path}"

          # Create the guest path if it doesn't exist
          machine.communicate.sudo("mkdir -p #{guest_path}")

          # Attempt to mount the folder. We retry here a few times because
          # it can fail early on.
          stderr = ""
          retryable(on: Errors::ParallelsMountFailed, tries: 3, sleep: 5) do
            machine.communicate.sudo(mount_command,
              error_class: Errors::ParallelsMountFailed,
              error_key: :parallels_mount_failed,
              command: mount_command,
              output: stderr,
            ) { |type, data| stderr = data if type == :stderr }
          end

          emit_upstart_notification(machine, guest_path)
        end

        def self.unmount_parallels_shared_folder(machine, guestpath, options)
          guest_path = Shellwords.escape(guestpath)

          result = machine.communicate.sudo("umount #{guest_path}", error_check: false)
          if result == 0
            machine.communicate.sudo("rmdir #{guest_path}", error_check: false)
          end
        end

        def self.prepare_psf_services(machine)
          # Parallels Tools for Linux includes native auto-mount script,
          # which causes loosing some of Vagrant-relative shared folders.
          # So, we should to disable this behavior. [GH-102]

          auto_mount_script = '/usr/bin/prlfsmountd'
          if machine.communicate.test("test -f #{auto_mount_script}")
            machine.communicate.sudo(
              "echo -e '#!/bin/sh\n'" +
                '# Shared folders auto-mount is disabled by Vagrant ' +
                "> #{auto_mount_script}")
          end
        end
      end
    end
  end
end

require 'rim/command_helper'
require 'rim/sync_module_helper'
require 'tempfile'

module RIM

class SyncHelper < CommandHelper

  def initialize(workspace_root, logger, module_infos = nil)
    @module_helpers = []
    super(workspace_root, logger, module_infos)
  end

  # called to add a module info
  def add_module_info(module_info)
    @module_helpers.push(SyncModuleHelper.new(@ws_root, module_info, @logger))
  end

  # sync all module changes into rim branch
  def sync
    check_ready
    # get the name of the current workspace branch
    RIM::git_session(@ws_root) do |s|
      branch = s.current_branch
      rim_branch = "rim/" + branch
      branch_sha1 = nil
      if branch.empty?
        raise RimException.new("Not on a git branch.")
      elsif branch.start_with?("rim/")
        raise RimException.new("The current git branch '#{branch}' is a rim integration branch. Please switch to a non rim branch to proceed.")
      else
        begin
          remote_rev = get_branch_start_revision(s, branch)
          rev = remote_rev ? remote_rev : branch
          branch_sha1 = s.rev_sha1(rev)
          checkout_rim_branch(s, rim_branch, rev)
          sync_modules
        ensure
          RIM::git_session(".") do |pwds|
            # Add a temporary file to avoid removal of working directory
            Tempfile.new(".untracked", ".")
            pwds.execute("git checkout #{branch}")
            pwds.execute("git reset --hard #{branch}")
            s.execute("git clean -xf -e .rim/")
            # We didn't remove any folders yet. This will be done now only for folders below the working directory
            pwds.execute("git clean -xdf -e .rim/")
          end
        end
      end
      if s.rev_sha1(rim_branch) != branch_sha1
        @logger.info("Changes have been commited to branch #{rim_branch}. Rebase to apply changes to workspace.")
      else
        @logger.info("No changes.")
      end
    end
  end

private
  # sync all modules
  def sync_modules
    each_module_parallel("sync'ing", @module_helpers) do |m|
      m.sync
    end
    @module_helpers.each do |m|
      m.commit
    end
  end

  # checkout the rim branch
  def checkout_rim_branch(session, rim_branch, rev)
      if !session.has_branch?(rim_branch) || !has_ancestor?(session, rim_branch, rev)
        # the destination branch is not existing or is not ancestor of the last remote revision
        # => create the branch at the remote revision 
        session.execute("git checkout -B #{rim_branch} #{rev}")
      else
        # the destination branch is yet existing and has the remote revision as ancestor
        # => put the changes onto the current branch
        session.execute("git checkout #{rim_branch}")
      end
  end

  # get revision where the branch should start
  def get_branch_start_revision(session, rev)
    # remote revs are where we stop traversal
    non_remote_revs = {}
    session.all_reachable_non_remote_revs(rev).each do |r| 
      non_remote_revs[r] = true
    end
    # make sure we deal only with sha1s
    rev = session.rev_sha1(rev)
    while rev && non_remote_revs[rev] && !has_changed_riminfo?(session, rev) 
      rev = get_parent(session, rev)
    end
    rev
  end

  # check whether revision has a changed .riminfo file
  def has_changed_riminfo?(session, rev)
    session.execute("git show --name-only --oneline #{rev}") =~ /\/\.riminfo$/
  end

  # check whether revision has a given ancestor
  def has_ancestor?(session, rev, ancestor)
    # make sure we deal only with sha1s
    rev = session.rev_sha1(rev)
    while rev && rev != ancestor
      rev = get_parent(session, rev)
    end
    rev != nil
  end
  
  # get first parent node
  def get_parent(session, rev)
    parents = session.parent_revs(rev)
    !parents.empty? ? parents.first : nil 
  end  

end

end

class Vlad::Git

  set :source, Vlad::Git.new
  set :git_cmd, "git"

  ##
  # Returns the command that will check out +revision+ from the
  # repository into directory +destination+.  +revision+ can be any
  # SHA1 or equivalent (e.g. branch, tag, etc...)

  def checkout(revision, destination)
    destination = 'repo' if destination == '.'
    revision = 'HEAD' if revision =~ /head/i

    [ "rm -rf #{destination}",
      "#{git_cmd} clone -q --depth 1 #{repository} #{destination}",
      "cd #{destination}",
      "#{git_cmd} submodule -q init",
      "#{git_cmd} submodule -q update"
    ].join(" && ")
  end

  def update(revision)
    "#{git_cmd} pull -q && #{git_cmd} submodule -q update"
  end

  ##
  # Returns the command that will export +revision+ from the repository into
  # the directory +destination+.

  def export(revision, destination)
    "mkdir -p #{destination} && cp -pR . #{destination}"
  end

  ##
  # Returns a command that maps human-friendly revision identifier +revision+
  # into a git SHA1.

  def revision(revision)
    revision = 'HEAD' if revision =~ /head/i

    "`#{git_cmd} rev-parse #{revision}`"
  end
end

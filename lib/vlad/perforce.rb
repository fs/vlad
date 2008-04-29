class Vlad::Perforce

  set :p4_cmd, "p4"
  set :source, Vlad::Perforce.new

  ##
  # Returns the p4 command that will checkout +revision+ into the directory
  # +destination+.

  def checkout(revision, destination)
    "#{p4_cmd} sync ...#{rev_no(revision)}"
  end

  ##
  # Returns the p4 command that will export +revision+ into the directory
  # +directory+.

  def export(revision_or_source, destination)
    if revision_or_source =~ /^(\d+|head)$/i then
      "(cd #{destination} && #{p4_cmd} sync ...#{rev_no(revision_or_source)})"
    else
      "cp -r #{revision_or_source} #{destination}"
    end
  end

  ##
  # Returns a command that maps human-friendly revision identifier +revision+
  # into a Perforce revision specification.

  def revision(revision)
    "`#{p4_cmd} changes -s submitted -m 1 ...#{rev_no(revision)} | cut -f 2 -d\\ `"
  end

  ##
  # Maps revision +revision+ into a Perforce revision.

  def rev_no(revision)
    case revision.to_s
    when /head/i then
      "#head"
    when /^\d+$/ then
      "@#{revision}"
    else
      revision
    end
  end
end

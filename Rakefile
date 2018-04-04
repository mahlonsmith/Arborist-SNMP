#!/usr/bin/env rake
# vim: set nosta noet ts=4 sw=4:

require 'pathname'

PROJECT = 'snmp'
BASEDIR = Pathname.new( __FILE__ ).expand_path.dirname.relative_path_from( Pathname.getwd )
LIBDIR  = BASEDIR + 'lib'

if Rake.application.options.trace
    $trace = true
    $stderr.puts '$trace is enabled'
end

# parse the current library version
$version = ( LIBDIR + 'arborist' + "#{PROJECT}.rb" ).read.split(/\n/).
	select{|line| line =~ /VERSION =/}.first.match(/([\d|.]+)/)[1]

task :default => [ :spec, :docs, :package ]


########################################################################
### P A C K A G I N G
########################################################################

require 'rubygems'
require 'rubygems/package_task'
spec = Gem::Specification.new do |s|
	s.email        = 'mahlon@martini.nu'
	s.homepage     = 'http://bitbucket.org/mahlon/Arborist-SNMP'
	s.authors      = [ 'Mahlon E. Smith <mahlon@martini.nu>', 'Michael Granger <ged@faeriemud.org>' ]
	s.platform     = Gem::Platform::RUBY
	s.summary      = "SNMP support for Arborist monitors"
	s.name         = 'arborist-' + PROJECT
	s.version      = $version
	s.license      = 'BSD-3-Clause'
	s.has_rdoc     = true
	s.require_path = 'lib'
	s.bindir       = 'bin'
	s.files        = File.read( __FILE__ ).split( /^__END__/, 2 ).last.split
	# s.executables  = %w[]
	s.description  = <<-EOF
	This library adds common SNMP resource support to Arborist monitors.
	EOF
	s.required_ruby_version = '>= 2'

	s.add_dependency 'arborist', "~> 0.1"
	s.add_dependency 'net-snmp2', "~> 0.3"
end

Gem::PackageTask.new( spec ) do |pkg|
	pkg.need_zip = true
	pkg.need_tar = true
end


########################################################################
### D O C U M E N T A T I O N
########################################################################

begin
	require 'rdoc/task'

	desc 'Generate rdoc documentation'
	RDoc::Task.new do |rdoc|
		rdoc.name       = :docs
		rdoc.rdoc_dir   = 'docs'
		rdoc.main       = "README.rdoc"
		rdoc.options    = [ '-f', 'fivefish' ]
		rdoc.rdoc_files = [ 'lib', *FileList['*.rdoc'] ]
	end

	RDoc::Task.new do |rdoc|
		rdoc.name       = :doc_coverage
		rdoc.options    = [ '-C1' ]
	end

rescue LoadError
	$stderr.puts "Omitting 'docs' tasks, rdoc doesn't seem to be installed."
end


########################################################################
### T E S T I N G
########################################################################

begin
    require 'rspec/core/rake_task'
    task :test => :spec

    desc "Run specs"
    RSpec::Core::RakeTask.new do |t|
        t.pattern = "spec/**/*_spec.rb"
    end

    desc "Build a coverage report"
    task :coverage do
        ENV[ 'COVERAGE' ] = "yep"
        Rake::Task[ :spec ].invoke
    end

rescue LoadError
    $stderr.puts "Omitting testing tasks, rspec doesn't seem to be installed."
end



########################################################################
### M A N I F E S T
########################################################################
__END__
lib/arborist/snmp.rb
lib/arborist/monitor/snmp.rb
lib/arborist/monitor/snmp/disk.rb
lib/arborist/monitor/snmp/process.rb
lib/arborist/monitor/snmp/memory.rb
lib/arborist/monitor/snmp/cpu.rb

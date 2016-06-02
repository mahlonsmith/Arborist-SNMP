# Arborist-SNMP

home
: http://bitbucket.org/mahlon/Arborist-SNMP

code
: http://code.martini.nu/Arborist-SNMP


## Description

Arborist is a monitoring toolkit that follows the UNIX philosophy
of small parts and loose coupling for stability, reliability, and
customizability.

This adds SNMP support to Arborist's monitoring, for things such as:

 - Disk space capacity
 - System load
 - Free memory
 - Swap in use
 - Running process checks


## Prerequisites

* Ruby 2.2 or better


## Installation

    $ gem install arborist-snmp


## Usage

In this example, we've created a resource node under an existing host, like so:

	Arborist::Host( 'example' ) do
		description "Example host"
		address     '10.6.0.169'
		resource 'load', description: 'machine load'
	end


From a monitor file, require this library, and create an snmp instance.
You can reuse a single instance, or create individual ones per monitor.


	require 'arborist/monitor/snmp'

	Arborist::Monitor '5 minute load average check' do
		every 30.seconds
		match type: 'resource', category: 'load'
		include_down true
		use :addresses

		snmp = Arborist::Monitor::SNMP.new( mode: 'load', load_error_at: 10 )
		exec( snmp )
	end

Please see the rdoc for all the mode types and error_at options.


## License

Copyright (c) 2016, Michael Granger and Mahlon E. Smith
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the author/s, nor the names of the project's
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.



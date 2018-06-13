
Arborist-SNMP
=============

home
: http://bitbucket.org/mahlon/Arborist-SNMP

code
: http://code.martini.nu/Arborist-SNMP


Description
-----------

Arborist is a monitoring toolkit that follows the UNIX philosophy
of small parts and loose coupling for stability, reliability, and
customizability.

This adds various SNMP support to Arborist's monitoring, specifically
for OIDS involving:

 - Disk space capacity
 - System CPU utilization
 - Memory and swap usage
 - Running process checks

It tries to provide sane defaults, while allowing fine grained settings
per resource node.  Both Windows and UCD-SNMP systems are supported.


Prerequisites
-------------

  * Ruby 2.3 or better


Installation
------------

    $ gem install arborist-snmp


Configuration
-------------

Global configuration overrides can be added to the Arborist config file,
under the `snmp` key.

The defaults are as follows:

```
arborist:
  snmp:
    timeout: 2
    retries: 1
    community: public
    version: 2c
    port: 161
    batchsize: 25
    cpu:
      warn_at: 80
    disk:
      warn_at: 90
      include: 
      exclude:
      - "^/dev(/.+)?$"
      - "/dev$"
      - "^/net(/.+)?$"
      - "/proc$"
      - "^/run$"
      - "^/sys/"
      - "/sys$"
    processes:
      check: []
    memory:
      physical_warn_at: 
      swap_warn_at: 60
```

The `warn_at` keys imply usage capacity as a percentage. ie:  "Warn me
when a disk mount point is at 90 percent utilization."


### Library Options

  * **timeout**: How long to wait for an SNMP response, in seconds?
  * **retries**: If an error occurs during SNMP communication, try again this many times before giving up.
  * **community**: The SNMP community name for reading data.
  * **version**: The SNMP protocol version.  v1, v2c, and v3 are supported.
  * **port**: The UDP port SNMP is listening on.
  * **batchsize**: How many hosts to gather SNMP data on simultaneously.


### Category Options and Behavior

#### CPU

  * **warn_at**: Set the node to a `warning` state when utilization is at or over this percentage.

Utilization takes into account CPU core counts, and uses the 5 minute
load average to calculate a percentage of current CPU use.

2 properties are set on the node. `cpu` contains the detected CPU count
and current utilization. `load` contains the 1, 5, and 15 minute load
averages of the machine.


#### Disk

  * **warn_at**: Set the node to a `warning` state when disk capacity is at or over this amount.
                 You can also set this to a Hash, keyed on mount name, if you want differing
                 warning values per mount point.  A mount point that is at 100% capacity will
                 be explicity set to `down`, as the resource it represents has been exhausted.
  * **include**: String or Array of Strings.  If present, only matching mount points are
                 considered while performing checks.  These are treated as regular expressions.
  * **exclude**: String or Array of Strings.  If present, matching mount point are removed
                 from evaluation.  These are treated as regular expressions.

A single property "mounts" is set on the node, which is a hash keyed by
mountpoint, with current capacity values.


#### Memory

  * **physical_warn_at**: Set the node to a `warning` state when RAM utilization is at or over this percentage.
  * **swap_warn_at**: Set the node to a `warning` state when swap utilization is at or over this percentage.

Warnings are only set for swap by default, since that is usually a
better indication of an impending problem.

2 properties are set on the node, "memory" and "swap".  Each is a Hash
that contains current usage and remaining available.


#### Processes

  * **check**: String or Array of Strings.  A list of processes to check if running.  These are
               treated as regular expressions, and include process arguments.

If any process in the list is not found in the process table, the
resource is set to a `down` state.

A single property is set on the node, a "counts" key that contains the
current number of running processes.


Examples
--------

In the simplest form, using default behaviors and settings, here's an
example Monitor configuration:

```
require 'arborist/snmp'

Arborist::Monitor 'cpu load check', :cpu do
	every 1.minute
	match type: 'resource', category: 'cpu'
	exec( Arborist::Monitor::SNMP::CPU )
end

Arborist::Monitor 'partition capacity', :disk do
	every 1.minute
	match type: 'resource', category: 'disk'
	exec( Arborist::Monitor::SNMP::Disk )
end

Arborist::Monitor 'process checks', :proc do
	every 1.minute
	match type: 'resource', category: 'process'
	exec( Arborist::Monitor::SNMP::Process )
end

Arborist::Monitor 'memory', :memory do
	every 1.minute
	match type: 'resource', category: 'memory'
	exec( Arborist::Monitor::SNMP::Memory )
end
```

Additionally, if you'd like these SNMP monitors to rely on the SNMP
service itself, you can add a UDP check for that.

```
Arborist::Monitor 'udp service checks', :udp do
	every 30.seconds
	match type: 'service', protocol: 'udp'
	exec( Arborist::Monitor::Socket::UDP )
end
```


And a default node declaration:

```
Arborist::Host 'example' do
	description 'An example host'
	address 'demo.example.com'

	resource 'cpu'
	resource 'memory'
	resource 'disk'
end
```



All configuration can be overridden from the defaults using the `config`
pragma, per node.  Here's a more elaborate example that performs the following:

  * All SNMP monitored resources are quieted if the SNMP service itself is unavailable.
  * Only monitor specific disk partitions, warning at different capacities .
  * Ensure the 'important' processing is running with the '--production' flag.
  * Warns at 95% memory utilization OR 10% swap.

-

```
Arborist::Host 'example' do
	description 'An example host'
	address 'demo.example.com'

	service 'snmp', protocol: 'udp'

	resource 'cpu', description: 'machine cpu load' do
		depends_on 'example-snmp'
	end

	resource 'memory', description: 'machine ram and swap' do
		depends_on 'example-snmp'
		config physical_warn_at: 95, swap_warn_at: 10
	end

	resource 'disk', description: 'partition capacity' do
		depends_on 'example-snmp'
		config \
			include: [
				'^/tmp',
				'^/var'
			],
			warn_at: {
					'/tmp' => 50,
					'/var' => 80
			}
	end

	resource 'process' do
		depends_on 'example-snmp'
		config check: 'important --production'
	end
end
```


## License

Copyright (c) 2016-2018 Michael Granger and Mahlon E. Smith
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



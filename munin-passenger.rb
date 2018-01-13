#!/root/.rbenv/shims/ruby

# Install

# wget https://raw.githubusercontent.com/tomlobato/munin-passenger5/master/munin-passenger.rb -O /usr/local/sbin/munin-passenger.rb
# chmod 755 /usr/local/sbin/munin-passenger.rb
# munin-passenger.rb install
# /etc/init.d/munin-node restart

require 'active_support/core_ext/hash/conversions'
require 'msgpack'
require 'ostruct'

class MuninPassenger

    CACHE_FILE = '/tmp/passenger_status_cache'
    CACHE_EXPIRE = 30

    GRAPHS = {
        # Global Passenger metrics
        global_pool: {
            level: :passenger,
            fields: {
                max: 'Max pool size',
                process_count: 'Process Count',
                get_wait_list_size: 'Requests in top-level queue'
            },
        },
        # App metrics
        processes: {
            level: :app,
            fields: {
                enabled_process_count: 'Enabled process Count',
                disabling_process_count: 'Disabling process Count',
                disabled_process_count: 'Disabled process Count',
            },
        },
        # App processes metrics: accounted by summing up metrics of all processes of the specific app
        app_queue: {
            level: :app_process,
            fields: {
                get_wait_list_size: 'App requests queue'
            },
        },
        cpu: {
            level: :app_process,
            fields: {
                cpu: '%CPU'
            }
        },
        sessions: {
            level: :app_process,
            fields: {
                sessions: 'Sessions'
            }
        },
        processed: {
            level: :app_process,
            fields: {
                processed: 'Processed'
            }
        },
        memory: {
            level: :app_process,
            fields: {
                rss: 'Resident Set Size',
                pss: 'Proportional Set Size',
                private_dirty: 'Private Dirty',
                swap: 'Swap',
                real_memory: 'Real Memory',
                vmsize: 'Virtual Memory Size',
            }
        }
    }

    def initialize argv
        @argv = argv
    end
        
    def cli 
        case @argv[0]
        when 'config'
            @param = get_params
            config
        when 'install'
            install
        else
            @param = get_params
            run
        end
    end

    private

    def config
        puts <<-CONFIG
graph_category Passenger
graph_title #{@param.app_name} #{@param.graph}
graph_vlabel count
graph_args --base 1000 -l 0
graph_info GI

CONFIG

        GRAPHS[@param.graph][:fields].each_pair do |k, v|
            puts "#{k}.label #{v}"
        end

        exit 0
    end

    def run
        data_global, data_app, data_app_processes = fetch

        count = {}

        case GRAPHS[@param.graph][:level]
        when :passenger
            fields.each do |field|
                count[field] = data_global[field].to_i
            end
        when :app
            fields.each do |field|
                count[field] = data_app[field].to_i
            end
        when :app_process
            data_app_processes.each do |process|
                fields.each do |k|
                    count[k] ||= 0
                    count[k] += process[k].to_i
                end
            end
        end

        count.each_pair do |k, v|
            puts "#{k}.value #{v}"
        end

        exit 0
    end

    # Util

    def fields
        GRAPHS[@param.graph][:fields]
            .keys
            .map(&:to_s)
    end

    def get_params        
        filename = File.basename __FILE__

        app_keys = []
        passenger_keys = []

        GRAPHS.each_pair do |k, v|
            if v[:level] == :passenger
                passenger_keys << k
            else
                app_keys << k
            end
        end

        if filename =~ /^passenger_(.*?)_(#{ app_keys.join '|' })$/ or
           filename =~ /^passenger_(#{ passenger_keys.join '|' })/
            if $2
                app_name = $1
                graph = $2
            else
                graph = $1
            end
            if app_name
                app_root = ENV['app_root']
                if !app_root or app_root.empty?
                    error "env.app_root not defined"
                end
            end
            OpenStruct.new(
                graph: graph.to_sym,
                app_name: app_name,
                app_root: app_root
            )
        else
            error "Invalid graph type for filename #{filename}."
        end
    end

    def fetch
        data_global = nil
        data_app = nil
        data_app_processes = nil

        # Global

        data_global = get_passenger_status

        # App

        supergroups = data_global['supergroups']['supergroup']
        supergroups = [supergroups] unless supergroups.is_a? Array
        supergroups.each do |_app|
            if _app['group']['app_root'] =~ /^#{@param.app_root}/
                data_app = _app['group']
            end
        end

        if !data_app
            error "App #{@param.app_name} (#{@param.app_root}) not found."
        end

        # App processes

        data_app_processes = data_app['processes']['process']

        case data_app_processes
        when Hash
            data_app_processes = [data_app_processes]
        when nil
            data_app_processes = []
        end
        
        [data_global, data_app, data_app_processes]
    end

    def get_passenger_status
        if File.exists? CACHE_FILE and
           (Time.now - File.stat(CACHE_FILE).ctime) < CACHE_EXPIRE and 
           false
           MessagePack.unpack File.open(CACHE_FILE, 'rb')
        else
            xml = `passenger-status --show=xml`
            pstatus = Hash.from_xml(xml)['info']
            File.open(CACHE_FILE, 'wb', 0600).write MessagePack.pack(pstatus)
            pstatus
        end
    end

    def get_apps
        supergroups = get_passenger_status['supergroups']['supergroup']
        supergroups = [supergroups] unless supergroups.is_a? Array
        supergroups.map{ |supergroup|
                app_root = supergroup['group']['app_root']
                app_name = app_root
                    .sub(/^\/var\/www/, '')
                    .sub(/\/current$/, '')
                    .sub(/^\/+|\/+$/, '')
                OpenStruct.new(app_name: app_name, app_root: app_root)
            }
    end

    def install
        apps = get_apps

        # Make Links

        links = []
        GRAPHS.keys.each do |graph|
            if GRAPHS[graph][:level] == :passenger
                links << graph
            else
                apps.each do |app|
                    links << "#{app.app_name}_#{graph}"
                end
            end
        end
        target = File.expand_path(__FILE__)
        links.each do |link|
            system "ln -s #{target} /etc/munin/plugins/passenger_#{link}"
        end

        # munin_node_conf

        munin_node_conf = "[passenger_*]
user root
env.PASSENGER_INSTANCE_REGISTRY_DIR /tmp/aptmp
"
        
        apps.each do |app|
            munin_node_conf += "
[passenger_#{app.app_name}_*]
env.app_root #{app.app_root}
"
        end

        munin_node_conf += "\n"

        File.open('/etc/munin/plugin-conf.d/munin-node', 'a').write munin_node_conf
    end

    def error msg
        STDERR.puts msg
        exit 1
    end
end

MuninPassenger.new(ARGV).cli


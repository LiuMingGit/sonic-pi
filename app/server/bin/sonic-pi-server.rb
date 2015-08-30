#!/usr/bin/env ruby
#--
# This file is part of Sonic Pi: http://sonic-pi.net
# Full project source: https://github.com/samaaron/sonic-pi
# License: https://github.com/samaaron/sonic-pi/blob/master/LICENSE.md
#
# Copyright 2013, 2014, 2015 by Sam Aaron (http://sam.aaron.name).
# All rights reserved.
#
# Permission is granted for use, copying, modification, and
# distribution of modified versions of this work as long as this
# notice is included.
#++

require 'cgi'

require_relative "../core.rb"
require_relative "../sonicpi/lib/sonicpi/studio"
require_relative "../sonicpi/lib/sonicpi/spider"
require_relative "../sonicpi/lib/sonicpi/spiderapi"
require_relative "../sonicpi/lib/sonicpi/server"
require_relative "../sonicpi/lib/sonicpi/util"
require_relative "../sonicpi/lib/sonicpi/oscencode"
require_relative "../sonicpi/lib/sonicpi/mods/minecraftpi"

os = case RUBY_PLATFORM
     when /.*arm.*-linux.*/
       :raspberry
     when /.*linux.*/
       :linux
     when /.*darwin.*/
       :osx
     when /.*mingw.*/
       :windows
     else
       RUBY_PLATFORM
     end

if os == :osx
  # Force sample rate for both input and output to 44k
  # If these are not identical, then scsynth will refuse
  # to boot.
  require 'coreaudio'
  CoreAudio.default_output_device(nominal_rate: 44100.0)
  CoreAudio.default_input_device(nominal_rate: 44100.0)
end

require 'multi_json'

include SonicPi::Util

server_port = ARGV[1] ? ARGV[0].to_i : 4557
client_port = ARGV[2] ? ARGV[1].to_i : 4558

protocol = case ARGV[0]
           when "-t"
            :tcp
           else
            :udp
           end

puts "Using protocol: #{protocol}"

ws_out = Queue.new
if protocol == :tcp
  gui = OSC::ClientOverTcp.new("127.0.0.1", client_port)
  encoder = SonicPi::StreamOscEncode.new(true)
else
  gui = OSC::Client.new("127.0.0.1", client_port)
  encoder = SonicPi::OscEncode.new(true)
end

begin
  if protocol == :tcp
    osc_server = OSC::ServerOverTcp.new(server_port)
  else
    osc_server = OSC::Server.new(server_port)
  end
rescue Exception => e
  m = encoder.encode_single_message("/exited-with-boot-error", ["Failed to open server port " + server_port.to_s + ", is scsynth already running?"])
  begin
    gui.send_raw(m)
  rescue Errno::EPIPE => e
    puts "GUI not listening, exit anyway."
  end
  exit
end


at_exit do
  m = encoder.encode_single_message("/exited")
  begin
    gui.send_raw(m)
  rescue Errno::EPIPE => e
    puts "GUI not listening."
  end
end

user_methods = Module.new
name = "SonicPiSpiderUser1" # this should be autogenerated
klass = Object.const_set name, Class.new(SonicPi::Spider)

klass.send(:include, user_methods)
klass.send(:include, SonicPi::SpiderAPI)
#klass.send(:include, SonicPi::Mods::SPMIDI)
klass.send(:include, SonicPi::Mods::Sound)
klass.send(:include, SonicPi::Mods::Minecraft)
begin
  sp =  klass.new "localhost", 4556, ws_out, 5, user_methods
rescue Exception => e
  puts "Failed to start server: " + e.message
  m = encoder.encode_single_message("/exited-with-boot-error", [e.message])
  gui.send_raw(m)
  exit
end

osc_server.add_method("/run-code") do |payload|
  begin
    #    puts "Received OSC: #{payload}"
    args = payload.to_a
    gui_id = args[0]
    code = args[1]
    sp.__spider_eval code
  rescue Exception => e
    puts "Received Exception!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/save-and-run-buffer") do |payload|
  begin
#    puts "Received save-and-run-buffer: #{payload.to_a}"
    args = payload.to_a
    gui_id = args[0]
    buffer_id = args[1]
    code = args[2]
    workspace = args[3]
    sp.__save_buffer(buffer_id, code)
    sp.__spider_eval code, {workspace: workspace}
  rescue Exception => e
    puts "Caught exception when attempting to save and run buffer!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/save-buffer") do |payload|
  begin
#    puts "Received save-buffer: #{payload.to_a}"
    args = payload.to_a
    gui_id = args[0]
    buffer_id = args[1]
    code = args[2]
    sp.__save_buffer(buffer_id, code)
  rescue Exception => e
    puts "Caught exception when attempting to save buffer!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/exit") do |payload|
  begin
    #  puts "exiting..."
    args = payload.to_a
    gui_id = args[0]
    sp.__exit
  rescue Exception => e
    puts "Received Exception when attempting to exit!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/stop-all-jobs") do |payload|
#  puts "stopping all jobs..."
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__stop_jobs
  rescue Exception => e
    puts "Received Exception when attempting to stop all jobs!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/load-buffer") do |payload|
#  puts "loading buffer..."
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__load_buffer args[1]
  rescue Exception => e
    puts "Received Exception when attempting to load buffer!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/complete-snippet-or-indent-selection") do |payload|
#  puts "indenting current line..."
  begin
    args = payload.to_a
    gui_id = args[0]
    id = args[1]
    buf = args[2]
    start_line = args[3]
    finish_line = args[4]
    point_line = args[5]
    point_index = args[6]
    sp.__complete_snippet_or_indent_lines(id, buf, start_line, finish_line, point_line, point_index)
  rescue Exception => e
    puts "Received Exception when attempting to indent current line!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/beautify-buffer") do |payload|
#  puts "beautifying buffer..."
  begin
    args = payload.to_a
    gui_id = args[0]
    id = args[1]
    buf = args[2]
    line = args[3]
    index = args[4]
    first_line = args[5]
    sp.__beautify_buffer(id, buf, line, index, first_line)
  rescue Exception => e
    puts "Received Exception when attempting to beautify buffer!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/ping") do |payload|
  #  puts "ping!"
  begin
    args = payload.to_a
    gui_id = args[0]
    id = args[1]
    m = encoder.encode_single_message("/ack", [id])
    gui.send_raw(m)
  rescue Exception => e
    puts "Received Exception when attempting to send ack!"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/start-recording") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.recording_start
  rescue Exception => e
    puts "Received Exception when attempting to start recording"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/stop-recording") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.recording_stop
  rescue Exception => e
    puts "Received Exception when attempting to stop recording"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/delete-recording") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.recording_delete
  rescue Exception => e
    puts "Received Exception when attempting to delete recording"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/save-recording") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    filename = payload.to_a[1]
    sp.recording_save(filename)
  rescue Exception => e
    puts "Received Exception when attempting to delete recording"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/reload") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    dir = File.dirname("#{File.absolute_path(__FILE__)}")
    Dir["#{dir}/../sonicpi/**/*.rb"].each do |d|
      load d
    end
    puts "reloaded"
  rescue Exception => e
    puts "Received Exception when attempting to reload files"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-invert-stereo") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_invert_stereo!
  rescue Exception => e
    puts "Received Exception when attempting to invert stereo"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-standard-stereo") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_standard_stereo!
  rescue Exception => e
    puts "Received Exception when attempting to set stereo to standard mode"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-stereo-mode") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_stereo_mode!
  rescue Exception => e
    puts "Received Exception when attempting to invert stereo"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-mono-mode") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_mono_mode!
  rescue Exception => e
    puts "Received Exception when attempting to switch to mono mode"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-hpf-enable") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    freq = args[1].to_f
    sp.set_mixer_hpf!(freq)
  rescue Exception => e
    puts "Received Exception when attempting to enable mixer hpf"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-hpf-disable") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_hpf_disable!
  rescue Exception => e
    puts "Received Exception when attempting to disable mixer hpf"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-lpf-enable") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    freq = args[1].to_f
    sp.set_mixer_lpf!(freq)
  rescue Exception => e
    puts "Received Exception when attempting to enable mixer lpf"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/mixer-lpf-disable") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.set_mixer_lpf_disable!
  rescue Exception => e
    puts "Received Exception when attempting to disable mixer lpf"
    puts e.message
    puts e.backtrace.inspect
  end
end


osc_server.add_method("/enable-update-checking") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__enable_update_checker
  rescue Exception => e
    puts "Received Exception when attempting to enable update checking"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/disable-update-checking") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__disable_update_checker
  rescue Exception => e
    puts "Received Exception when attempting to disable update checking"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/check-for-updates-now") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__update_gui_version_info_now
  rescue Exception => e
    puts "Received Exception when attempting to check for latest version now"
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/version") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    v = sp.__current_version
    lv = sp.__server_version
    lc = sp.__last_update_check
    plat = host_platform_desc
    m = encoder.encode_single_message("/version", [v.to_s, v.to_i, lv.to_s, lv.to_i, lc.day, lc.month, lc.year, plat.to_s])
    gui.send_raw(m)
  rescue Exception => e
    puts "Received Exception when attempting to check for version "
    puts e.message
    puts e.backtrace.inspect
  end
end

osc_server.add_method("/gui-heartbeat") do |payload|
  begin
    args = payload.to_a
    gui_id = args[0]
    sp.__gui_heartbeat gui_id
  rescue Exception => e
    puts "Received Exception when attempting to handle gui heartbeat"
    puts e.message
    puts e.backtrace.inspect
  end
end

if protocol == :tcp
  Thread.new{osc_server.safe_run}
else
  Thread.new{osc_server.run}
end

# Send stuff out from Sonic Pi back out to osc_server
out_t = Thread.new do
  continue = true
  while continue
    begin
      message = ws_out.pop
      # message[:ts] = Time.now.strftime("%H:%M:%S")

      if message[:type] == :exit
        m = encoder.encode_single_message("/exited")
        begin
          gui.send_raw(m)
        rescue Errno::EPIPE => e
          puts "GUI not listening, exit anyway."
        end
        continue = false
      else
        case message[:type]
        when :multi_message
          m = encoder.encode_single_message("/multi_message", [message[:jobid], message[:thread_name].to_s, message[:runtime].to_s, message[:val].size, *message[:val].flatten])
          gui.send_raw(m)
        when :info
          m = encoder.encode_single_message("/info", [message[:val]])
          gui.send_raw(m)
        when :syntax_error
          desc = message[:val] || ""
          line = message[:line] || -1
          error_line = message[:error_line] || ""
          desc = CGI.escapeHTML(desc)
          m = encoder.encode_single_message("/syntax_error", [message[:jobid], desc, error_line, line, line.to_s])
          gui.send_raw(m)
        when :error
          desc = message[:val] || ""
          trace = message[:backtrace].join("\n")
          line = message[:line] || -1
          # TODO: Move this escaping to the Qt Client
          desc = CGI.escapeHTML(desc)
          trace = CGI.escapeHTML(trace)
          # puts "sending: /error #{desc}, #{trace}"
          m = encoder.encode_single_message("/error", [message[:jobid], desc, trace, line])
          gui.send_raw(m)
        when "replace-buffer"
          buf_id = message[:buffer_id]
          content = message[:val] || "Internal error within a fn calling replace-buffer without a :val payload"
          line = message[:line] || 0
          index = message[:index] || 0
          first_line = message[:first_line] || 0
#          puts "replacing buffer #{buf_id}, #{content}"
          m = encoder.encode_single_message("/replace-buffer", [buf_id, content, line, index, first_line])
          gui.send_raw(m)
        when "replace-lines"
          buf_id = message[:buffer_id]
          content = message[:val] || "Internal error within a fn calling replace-line without a :val payload"
          point_line = message[:point_line] || 0
          point_index = message[:point_index] || 0
          start_line = message[:start_line] || point_line
          finish_line = message[:finish_line] || start_line
#          puts "replacing line #{buf_id}, #{content}"
          m = encoder.encode_single_message("/replace-lines", [buf_id, content, start_line, finish_line, point_line, point_index])
          gui.send_raw(m)
        when :version
          v = message[:version]
          v_num = message[:version_num]
          lv = message[:latest_version]
          lv_num = message[:latest_version_num]
          lc = message[:last_checked]
          m = encoder.encode_single_message("/version", [v.to_s, v_num.to_i, lv.to_s, lv_num.to_i, lc.day, lc.month, lc.year])
          gui.send_raw(m)
        else
          puts "ignoring #{message}"
        end

      end
    rescue Exception => e
      puts "Exception!"
      puts e.message
      puts e.backtrace.inspect
    end
  end
end

out_t.join

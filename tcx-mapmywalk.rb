#!/usr/bin/env ruby

#--------------------
# Description:
#   download tcx files from mapmywalk.com
#
# Usage:
#   tcx-mapmaywalk.rb -u <usernmae> -p <password> -P <proxyhost:port> -d <dir> <yyyymm[dd]>
#     "-P" option can be ommited, if so no proxy environment
#     "-d" option can be ommited, if so defalut value is "tcx-mapmywalk"
#     After execution of this program, tcx files are downloaded under "mapmywalk" subdirectory.
#
# Ex1. download tcx files of specific month
#   $ ruby tcx-mapmaywalk.rb -u username@example.com -p abc123 -P proxy.example.com:8080 201603
#
# Ex2. download tcx files of specific date
#   $ ruby tcx-mapmaywalk.rb -u username@example.com -p abc123 -P proxy.example.com:8080 20160310
#
#--------------------

#--------------------
# required gems
#--------------------

require 'time'
require 'date'
require 'rubygems'
require 'json'
require 'mechanize'
require 'rexml/document'
require 'optparse'

#--------------------
# parse command line
#--------------------

# option spec
begin
  options = ARGV.getopts('u:p:P:d:', 'user:', 'password:', 'proxy:', 'dir:')
rescue
  puts "Error: Missing Argument\n"
  exit
end

# initialize vars
username = nil
password = nil
proxy = nil
proxyhost = nil
proxyport = nil
dir = "tcx-mapmywalk"
arg_ymd = nil

# parse options
options.each do |key, val|
  case key
    when "u","user"
      username ||= val
    when "p","password"
      password ||= val
    when "P","proxy"
      proxy ||= val
      proxyhost, proxyport = proxy.split(/:/) unless proxy == nil
    when "d","dir"
      dir = val || dir
  end
end

# parse args
arg_ymd = ARGV[0].strip unless ARGV[0] == nil
arg_year = nil
arg_month = nil
arg_day = nil
if arg_ymd =~ /^\d{4}\d{2}$/ then
  arg_year = arg_ymd[0,4].to_i
  arg_month =  arg_ymd[4,2].to_i
elsif arg_ymd =~ /^\d{4}\d{2}\d{2}$/ then
  arg_year = arg_ymd[0,4].to_i
  arg_month =  arg_ymd[4,2].to_i
  arg_day =  arg_ymd[6,2].to_i
else
end

# param error check
err_msg = ""
err_cnt = 0
if username == nil
  err_cnt+=1
  err_msg << "Error: '-u, --user' missing value.\n"
end
if password == nil
  err_cnt+=1
  err_msg << "Error: '-p, --password' missing value.\n"
end
if arg_ymd == nil
  err_cnt+=1
  err_msg << "Error: 'yyyymm[dd]' missing.\n"
end

# exit if error
if err_cnt > 0 then
  puts err_msg
  exit(1)
end


#--------------------
# define mapmywalk urls
#--------------------

LOGIN_URL = "https://www.mapmywalk.com/auth/login/"
# http://www.mapmywalk.com/workouts/dashboard.json?month=2&year=2016
WORKOUTS = "http://www.mapmywalk.com/workouts/dashboard.json?month=%s&year=%s"
TCX_EXPORT = "http://www.mapmywalk.com/workout/export/%s/tcx"

#--------------------
# create sub directory
#--------------------

FileUtils.mkdir_p(dir)
# remove previous files
#FileUtils.rm_rf(Dir.glob(dir + '/*'))

#--------------------
# Mechanize
#--------------------

agent = Mechanize.new
agent.follow_meta_refresh = true
agent.user_agent_alias = 'Mac Safari'
if proxyhost != nil then
  agent.set_proxy(proxyhost, proxyport.to_i, nil, nil)
end

#--------------------
# Login to mapmywalk.com
#--------------------

# get login page
begin
  login_page = agent.get(LOGIN_URL)
rescue SocketError => ex
  puts "Error: cannot connect to 'mapmywalk.com'."
  puts "#{ex}"
  exit(1);
rescue
  raise
end

# submit login-form
form = login_page.forms[0]
form.field_with(:id => 'id_email').value = username
form.field_with(:id => 'id_password').value = password
begin
  form_result = form.click_button
rescue
  puts "mapmywalk login failed."
  exit(1);
else
  puts "mapmywalk login successful."
end

#--------------------
# list of workouts of year/month
#--------------------

json = agent.get(WORKOUTS % [arg_month.to_s, arg_year.to_s])
json.save!(File.join(dir, "workouts-%4d%02d.json" % [arg_year, arg_month]))
json_parse = JSON.parse(json.body)

workout_ids = []
dayworkouts = json_parse['workout_data']['workouts']
dayworkouts.each_pair do |date, workouts|
  workouts.each do |workout|
    workout_id = workout['view_url'].sub(%r'/workout/','')
    workout_date = workout['date']
    #d = Date.strptime(date, "%Y-%m-%d")
    d = Date.strptime(workout_date, "%m/%d/%Y")
    if arg_day == nil then
      if (d.year == arg_year) && (d.month == arg_month) then
        #puts "##{workout_ids.length} workout_id=#{workout_id} date=#{d.strftime("%Y-%m-%d")}"
        workout_ids << workout_id
      end
    else
      if (d.year == arg_year) && (d.month == arg_month) && (d.day == arg_day)then
        #puts "##{workout_ids.length} workout_id=#{workout_id} date=#{d.strftime("%Y-%m-%d")}"
        workout_ids << workout_id
      end
    end
  end
end

workout_ids.each do |workout_id|
  #p workout_id
  xmldoc = agent.get(TCX_EXPORT % workout_id)
  xmlbody = REXML::Document.new(xmldoc.body)
  strtime = xmlbody.elements['TrainingCenterDatabase/Activities/Activity/Id'].text.strip
  strlocaltime = Time.parse(strtime).localtime.to_s
  year, month, day, hour, min, sec, timezone = strlocaltime.split(/[\ \-\:]/)
  fname = "%s%s%s-%s%s-%s.tcx" % [year, month, day, hour, min, workout_id]
  xmldoc.save!(File.join(dir, fname))
  puts "%s" % fname
end

puts "total #{workout_ids.count} tcx files downloaded."

#--------------------
# end of program
#--------------------

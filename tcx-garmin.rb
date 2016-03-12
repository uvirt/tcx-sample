#!/usr/bin/env ruby

#--------------------
# Description:
#   download tcx files from connect.garmin.com
#
# Usage:
#   tcx-garmin.rb -u <usernmae> -p <password> -P <proxyhost:port> -d <dir> <yyyymm[dd]>
#     "-P" option can be ommited, if so no proxy environment
#     "-d" option can be ommited, if so defalut value is "tcx-garmin"
# Usage:
#
# Syntax:
#   tcx-garmin.rb -u <usernmae> -p <password> -P <proxyhost:port> -d <dir> <yyyymm[dd]>
#     -P options can be ommited
#     -d options can be ommited, if so defalut value is "tcx-garmin"
#     After execution of this program, tcx files are downloaded under "tcx-garmin" subdirectory.
#
# Ex1. download tcx files of specific month
#   $ ruby tcx-garmin.rb -u username@example.com -p abc123 -P proxy.example.com:8080 201603
#
# Ex2. download tcx files of specific date
#   $ ruby tcx-garmin.rb -u username@example.com -p abc123 -P proxy.example.com:8080 20160310
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
dir = "tcx-garmin"
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
# define garmin urls
#--------------------

LOGIN_URL = "https://sso.garmin.com/sso/login"
ACTIVITIES = "https://connect.garmin.com/proxy/activity-search-service-1.0/json/activities?start=0&limit=100"
TCX_EXPORT = "https://connect.garmin.com/proxy/activity-service-1.2/tcx/activity/%s?full=true"

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
# Login to connect.garmin.com
#--------------------

# get login page
begin
  login_page = agent.get(LOGIN_URL, {
    'service' => 'https://connect.garmin.com/post-auth/login',
    'webhost' => 'olaxpw-connect13.garmin.com',
    'source' => 'https://connect.garmin.com/en-US/signin',
    'redirectAfterAccountLoginUrl' => 'https://connect.garmin.com/post-auth/login',
    'redirectAfterAccountCreationUrl' => 'https://connect.garmin.com/post-auth/login',
    'gauthHost' => 'https://sso.garmin.com/sso',
    'locale' => 'en_US',
    'id' => 'gauth-widget',
    'cssUrl' => 'https://static.garmincdn.com/com.garmin.connect/ui/css/gauth-custom-v1.2-min.css',
    'clientId' => 'GarminConnect',
    'rememberMeShown' => 'true',
    'rememberMeChecked' => 'false',
    'createAccountShown' => 'true',
    'openCreateAccount' => 'false',
    'usernameShown' => 'false',
    'displayNameShown' => 'false',
    'consumeServiceTicket' => 'false',
    'initialFocus' => 'true',
    'embedWidget' => 'false',
    'generateExtraServiceTicket' => 'false',
})
rescue SocketError => ex
  puts "Error: cannot connect to 'garmin.com'."
  puts "#{ex}"
  exit(1);
rescue
  raise
end

# get login-form
form = login_page.form_with(:id => 'login-form')

# submit login-form
form.field_with(:id => 'username').value = username
form.field_with(:id => 'password').value = password
form_result = form.click_button

# get response_url
response_url = form_result.body.scan(/var\s\s*response_url\s*=\s*'(.*)';/).flatten.first
response = agent.get(response_url)

#--------------------
# get list of activities from JSON
#--------------------

begin
  json = agent.get(ACTIVITIES)
rescue
  puts "Error: garmin login failed."
  exit(1);
else
  puts "garmin login successful."
end

json.save!(File.join(dir, "activities.json"))
json_parse = JSON.parse(json.body)
activities = json_parse['results']['activities']

#--------------------
# list activities
#--------------------

activityIds = []
activities.each_with_index do |a,i|
  activityId = a['activity']['activityId']
  activityName = a['activity']['activityName']['value']
  beginTimestamp = Time.at((a['activity']['beginTimestamp']['millis'].to_i/1000.0).round)
  endTimestamp = Time.at((a['activity']['endTimestamp']['millis'].to_i/1000.0).round)

  if arg_day == nil then
    if (beginTimestamp.year == arg_year) && (beginTimestamp.month == arg_month) then
      #puts "##{activityIds.length} activityId=#{activityId} Time=#{beginTimestamp.strftime('%Y-%m-%d %H:%M')} #{activityName}"
      activityIds << activityId
    end
  else
    if (beginTimestamp.year == arg_year) && (beginTimestamp.month == arg_month) && (beginTimestamp.day == arg_day) then
      #puts "##{activityIds.length} activityId=#{activityId} Time=#{beginTimestamp.strftime('%Y-%m-%d %H:%M')} #{activityName}"
      activityIds << activityId
    end
  end
end

#--------------------
# download tcx files under dir
#--------------------

activityIds.each do |activityId|
  xmldoc = agent.get(TCX_EXPORT % activityId)
  xmlbody = REXML::Document.new(xmldoc.body)
  strtime = xmlbody.elements['TrainingCenterDatabase/Activities/Activity/Id'].text.strip
  strlocaltime = Time.parse(strtime).localtime.to_s
  year, month, day, hour, min, sec, timezone = strlocaltime.split(/[\ \-\:]/)
  fname = "%s%s%s-%s%s-%s.tcx" % [year, month, day, hour, min, activityId]
  xmldoc.save!(File.join(dir, fname))
  puts "%s" % fname
end
puts "total #{activityIds.count} tcx files downloaded."

#--------------------
# end of program
#--------------------

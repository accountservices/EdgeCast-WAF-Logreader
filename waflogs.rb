#!/usr/bin/env ruby

require 'net/http'
require 'net/https'
require 'date'
require 'json'
require 'gserver'
require 'logger'


class HealthCheckServer < GServer
  def initialize(port=ENV['PORT'].to_i, *args)
    super(port, *args)
  end
  def serve(io)
    response = "OK\n"
    io.puts("HTTP/1.1 200 OK\r\n" +
                "Content-Type: text/plain\r\n" +
                "Content-Length: #{response.bytesize}\r\n" +
                "Connection: close\r\n\r\n")
    io.puts(response)
  end
end

puts 'Starting up...'
# Run the server with logging enabled (it's a separate thread).
server = HealthCheckServer.new
server.audit = false                  # Turn logging on.
server.start

puts ENV['EDGECAST_ACCOUNT'] || 'Missing EDGECAST_ACCOUNT'
puts ENV['LOG_PATH'] || 'Missing LOG_PATH'
puts ENV['FILE'] || 'Missing FILE'
puts ENV['INTERVAL'] || 'Missing INTERVAL'
puts ENV['OFFSET'] || 'Missing OFFSET'
puts ENV['FILTER'] || 'Missing FILTER'
puts ENV['EDGECAST_REST_TOKEN'] || 'Missing EDGECAST_REST_TOKEN'

url_to_account = 'https://api.edgecast.com/v2/mcc/customers/' + ENV['EDGECAST_ACCOUNT'] + '/waf/eventlogs'

class Logger::LogDevice
  def add_log_header(file)
  end
end

logger = Logger.new(ENV['LOG_PATH'] + ENV['FILE'] + '.log', 10, 1024*1024)
logger.formatter = proc do |severity, datetime, progname, msg|
  "#{msg}\n"
end

def fetch_feed url
  urltemp = URI.parse(url)
  https = Net::HTTP.new(urltemp.host, urltemp.port)
  https.use_ssl = (urltemp.scheme == 'https')
  request = Net::HTTP::Get.new(url)
  request['Authorization'] = 'TOK:' + ENV['EDGECAST_REST_TOKEN']
  return https.request(request)
end

interval = ENV['INTERVAL'].to_i
offset = ENV['OFFSET'].to_i
filter = ENV['FILTER']

loop {
  url = url_to_account
  now = (DateTime.now - Rational(offset, 24)).strftime('%Y-%m-%dT%H:%M')
  five_minutes_ago = (DateTime.now - Rational(offset, 24) - Rational(interval, 86400)).strftime('%Y-%m-%dT%H:%M')
  url = url + '?start_time=' + five_minutes_ago
  url = url + '&end_time=' + now

  unless filter.nil?
    url = url + '&filters=' + filter.to_s
  end

  response = fetch_feed(url)
  result = JSON.parse(response.body)

  pages = result['page_of']
  for page in 1..pages
    response = fetch_feed(url+'&page=' + page.to_s)
    result = JSON.parse(response.body)
    result['events'].each { |event| logger.info(JSON.generate(event)) }
  end
  sleep interval
}


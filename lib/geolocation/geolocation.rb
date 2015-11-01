require 'net/http'
require_relative '../../lib/error'


module Geolocations
  class Geolocation
    SEPARATOR = ";"
    include Errors
    attr_accessor :country,
                  :protocol,
                  :ip,
                  :port,
                  :user,
                  :password

    def initialize(geo_line)
      # accepte les hsotname ou les @ip pour <ip>

      r = /(?<country>.*)#{SEPARATOR}(?<protocol>http|HTTP|https|HTTPS);(?<ip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}|.*\..*\..*);(?<port>\d{1,5});(?<user>.*);(?<password>.*)/.match(geo_line)
      unless r.nil?
        @country = r[:country]
        @protocol = r[:protocol]
        @ip = r[:ip]
        @port = r[:port]
        @user = r[:user]
        @password = r[:password]
      else
        raise Error.new(GEO_BAD_PROPERTIES, :values => {:geo => geo_line})
      end
    end

    def available?
      begin
        response = Net::HTTP::Proxy(@ip, @port).start('www.ruby-doc.org') { |http|}
      rescue Exception => e
        case response
          when Net::HTTPSuccess
            true
          else
            raise Error.new(GEO_NOT_AVAILABLE, :values => {:geo => to_s})
        end
      end
    end

    def to_s
      "#{@country} - #{@protocol} - #{@ip} - #{@port} - #{@user} - #{@password}"
    end


    def to_json
      {:country => @country,
       :protocol => @protocol,
       :ip => @ip,
       :port => @port,
       :user => @user,
       :pwd => @password
      }
    end
  end
end
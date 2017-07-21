require_relative '../flow'
require_relative '../error'
require_relative 'geolocation'
require 'eventmachine'

module Geolocations
  #----------------------------------------------------------------------------------------------------------------
  # include class
  #----------------------------------------------------------------------------------------------------------------
  include Errors
  #----------------------------------------------------------------------------------------------------------------
  # Message exception
  #----------------------------------------------------------------------------------------------------------------

  ARGUMENT_UNDEFINE = 1300
  NONE_GEOLOCATION = 1301
  GEO_BAD_PROPERTIES = 1302
  GEO_NOT_AVAILABLE = 1303
  GEO_FILE_NOT_FOUND = 1304
  GEO_NONE_COMPLIANT = 1305
  GEO_NOT_VALID = 1306

  class GeolocationFactory
    include Errors

    EOFLINE ="\n"
    attr :geolocations,
         :geolocations_file,
         :logger

    TMP = File.expand_path(File.join("..", "..","..",  "tmp"), __FILE__)

    def initialize(delay_periodic_load, logger)
      @logger = logger


      begin
        raise Error.new(ARGUMENT_UNDEFINE, :values => {:variable => "delay_periodic_load"}) if delay_periodic_load.nil?

        basename = ["geolocations", "none" ,$staging, Date.today.strftime("%Y-%m-%d")].join("_")
        absolute_path = File.join(TMP, "#{basename}.txt")

        @geolocations_file = Flow.from_absolute_path(absolute_path).last


        raise Error.new(GEO_FILE_NOT_FOUND, :values => {:path => @geolocations_file.absolute_path}) if @geolocations_file.nil?

        @geolocations = []

        #premier chargement pour eviter d'avoir des erreur, car l'EM::periodic déclenche dans le dealy et pas à zero
        load

        EM.add_periodic_timer(delay_periodic_load) do
          load
        end

      rescue Exception => e
        raise e

      rescue Exception => e
        @logger.an_event.error e.message
        retry

      else
        @logger.an_event.debug "geolocations factory create"

      ensure


      end
    end


    def clear
      #@geolocations.each { |geo| @geolocations.delete(geo) }
      @geolocations = []
    end


    # retourne un objet geolocation ou
    # retourne une exception si plus aucun geolocation dans la factory
    # retourne une exception si plus aucun geolocation ne satisfait les criteres

    def get(criteria={})

      geo_count = @geolocations.size
      i = 1

      begin

        geo = select
        raise Error.new(GEO_NOT_VALID, :values => {:country => criteria[:country], :protocol => criteria[:protocol]}) if (!criteria[:country].nil? and criteria[:country].downcase != geo.country.downcase) or
            (!criteria[:protocol].nil? and criteria[:protocol].downcase != geo.protocol.downcase)

      rescue Exception => e

        case e.code
          when NONE_GEOLOCATION
            @logger.an_event.error e.message
            raise e
          when GEO_NOT_VALID
            if i < geo_count
              i += 1
              @logger.an_event.warn e.message
              retry
            else
              @logger.an_event.error e.message
              raise Error.new(GEO_NONE_COMPLIANT)
            end
        end
      else
        #on sort de la boucle :
        # soit on a trouve une geo qui repond aux criteres passés si il y en a
        # soit parce que on les a passé tous les geo et il n'y a aucun geolocation qui satisfont les critères => exception
        @logger.an_event.info "geolocation find : #{geo.to_s}"
        return geo
      ensure

      end
    end


    def to_s
      @geolocations.join("\n")
    end

    def load
      clear

      @geolocations_file.foreach(EOFLINE) { |geo_line|

        begin

          @geolocations << Geolocation.new(geo_line)

        rescue Exception => e

          @logger.an_event.warn e.message

        end
      }

      @geolocations_file.close

      @logger.an_event.info "#{@geolocations.size} geolocation(s) loaded"

    end

    private

    # retourne un objet geolocation ou
    # retourne une exception si plus aucun geolocation dans la factory
    def select

      begin

        raise Error.new(NONE_GEOLOCATION) if @geolocations.size == 0

        geo = @geolocations.shift

        geo.available?

        #geo.transparent?()

      rescue Exception => e

        case e.code
          when NONE_GEOLOCATION
            @logger.an_event.warn e.message
            raise e

          when GEO_NOT_AVAILABLE
            @logger.an_event.warn e.message
            retry

          else
            @logger.an_event.error e.message
        end

      else
        # on range la gelocation pour conserver une file tournante.
        @geolocations << geo
        @logger.an_event.debug "geolocation #{geo.to_s} select"
        return geo
      ensure

      end

    end
  end
end
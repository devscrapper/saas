require 'net/ftp'
require 'pathname'
require 'ruby-progressbar'
require_relative 'communication'
require_relative 'logging'
require_relative 'authentification'

class Flow
  class FlowException < StandardError;
  end
  PROGRESS_BAR_SIZE = 180
  MAX_SIZE = 1000000 # taille max d'un volume
  SEPARATOR = "_" # separateur entre elemet composant (type_flow, label, date, vol) le nom du volume (basename)
  ARCHIVE = File.expand_path(File.join("..", "..", "archive"), __FILE__) #localisation du repertoire d'archive
  FORBIDDEN_CHAR = /[_ ]/ # liste des caractères interdits dans le typeflow et label d'un volume
  attr :descriptor,
       :dir,
       :type_flow,
       :ext,
       :logger

  attr_reader :label, :vol, :date, :policy

  #----------------------------------------------------------------------------------------------------------------
  # class methods
  #----------------------------------------------------------------------------------------------------------------
  #----------------------------------------------------------------------------------------------------------------
  # self.last(dir, opts)
  #----------------------------------------------------------------------------------------------------------------
  # fournit le flow le plus récent présent dans le <dir> et qui satisfait les options
  #----------------------------------------------------------------------------------------------------------------
  # input :
  # un répertoire, ne doit pas être nil
  # :typeflow : un type de flow : si est absent alors n'intervient pas dans la recherche
  # :label : un label : si est absent alors n'intervient pas dans la recherche
  # :date : une date : si est absent alors n'intervient pas dans la recherche
  # :ext : une extension de fichier : si est absent alors n'intervient pas dans la recherche
  #----------------------------------------------------------------------------------------------------------------
  def self.last(dir, opts)
    arr = Flow.list(dir, opts)
    raise FlowException, "none flow #{opts} exist in #{dir}" if arr.empty?
    arr[0].last
  end

  #----------------------------------------------------------------------------------------------------------------
  # self.list(dir, opts)
  #----------------------------------------------------------------------------------------------------------------
  # fournit la liste des flow présent dans le <dir> et qui satisfont les options
  #----------------------------------------------------------------------------------------------------------------
  # input :
  # un répertoire, ne doit pas être nil
  # :typeflow : un type de flow : si est absent alors n'intervient pas dans la recherche
  # :label : un label : si est absent alors n'intervient pas dans la recherche
  # :date : une date : si est absent alors n'intervient pas dans la recherche
  # :ext : une extension de fichier : si est absent alors n'intervient pas dans la recherche
  #----------------------------------------------------------------------------------------------------------------
  def self.list(dir, opts={})
    type_flow = opts.fetch(:type_flow, "*").gsub(FORBIDDEN_CHAR, "-")
    label = opts.fetch(:label, "*").gsub(FORBIDDEN_CHAR, "-")
    policy = opts.fetch(:policy, "*").to_s
    date = opts.fetch(:date, "*")
    date = date.strftime("%Y-%m-%d") if date.is_a?(Date)
    ext = opts.fetch(:ext, ".*")
    Dir.glob(File.join(dir, "#{type_flow}#{SEPARATOR}#{policy}#{SEPARATOR}#{label}#{SEPARATOR}#{date}*#{ext}")).map { |file| Flow.from_absolute_path(file) }
  end

  #----------------------------------------------------------------------------------------------------------------
  # self.from_basename(dir, basename)
  #----------------------------------------------------------------------------------------------------------------
  # Construit un Flow
  #----------------------------------------------------------------------------------------------------------------
  # input : un répertoire, un nom de fichier avec une extension
  # le nom du fichier doit contenir :
  # type_flow
  # label
  # date
  # vol
  # separé par #{SEPARATOR}
  #----------------------------------------------------------------------------------------------------------------
  def self.from_basename(dir, basename)
    #basename ne doit être nil
    ext = File.extname(basename)
    basename = File.basename(basename, ext)
    type_flow, policy, label, date, vol = basename.split(SEPARATOR)

    Flow.new(dir, type_flow, policy, label, date, vol, ext)
  end

  #----------------------------------------------------------------------------------------------------------------
  # self.from_absolute_path(absolute_path)
  #----------------------------------------------------------------------------------------------------------------
  # Construit un Flow
  #----------------------------------------------------------------------------------------------------------------
  # input : un répertoire, un nom de fichier avec une extension
  # le nom du fichier doit contenir :
  # type_flow
  # label
  # date
  # vol
  # separé par #{SEPARATOR}
  #----------------------------------------------------------------------------------------------------------------
  # Construit un Flow
  #----------------------------------------------------------------------------------------------------------------
  # input : le nom absolu d'un fichier (path+nanme+extension)
  #----------------------------------------------------------------------------------------------------------------
  def self.from_absolute_path(absolute_path)
    dir = File.dirname(absolute_path)
    basename = File.basename(absolute_path)
    Flow.from_basename(dir, basename)
  end

  #----------------------------------------------------------------------------------------------------------------
  # instance methods
  #----------------------------------------------------------------------------------------------------------------
  def initialize(dir, type_flow, policy, label, date, vol=nil, ext=".txt")
    # si rdir est un pathname alors on le transforme en string
    @dir = dir.to_s
    @type_flow = type_flow.gsub(FORBIDDEN_CHAR, "-") #le label ne doit pas contenir les caractères interdits
    @policy = policy.is_a?(Symbol) ? policy.to_s : policy
    @label = label.gsub(FORBIDDEN_CHAR, "-") #le label ne doit pas contenir les caractères interdits
    @date = date
    @date = date.strftime("%Y-%m-%d") if date.is_a?(Date)
    @date = "#{date.year}-#{date.month}-#{date.day}-#{date.hour}-#{date.min}-#{date.sec}" if date.is_a?(Time)
    @vol = vol.to_s unless vol.nil?
    @ext = ext
    # @logger = Logging::Log.new(self, :staging => $staging, :debugging => $debugging)
    @logger = Logging::Log.new(self, :staging => $staging, :debugging => false)
    if !(@dir && @type_flow && @policy && @label && @date && @ext) and $debugging
      @logger.an_event.debug "dir <#{@dir}>"
      @logger.an_event.debug "type_flow <#{@type_flow}>"
      @logger.an_event.debug "policy <#{@policy}>"
      @logger.an_event.debug "label <#{@label}>"
      @logger.an_event.debug "date <#{@date}>"
      @logger.an_event.debug "vol <#{@vol}>"
      @logger.an_event.debug "ext <#{@ext}>"
      @logger.an_event.debug "details flow <#{self.to_s}>"
    end
    raise FlowException, "Flow not initialize" unless @dir && @type_flow && policy && @label && @date && @ext
  end

  def == (flow)
    #les volumes et leur nombre ne sont pas pris en compte, car c'est une egalité fonctionnelle et pas technique
    @dir == flow.dir &&
        @type_flow == flow.type_flow &&
        @policy == flow.policy &&
        @label == flow.label &&
        @date == flow.date &&
        @ext == flow.ext
  end

  def <(flow)
    # est utilisé pour ordonner les flow dans le temps
    # ne DOIT etre utilisé que pour les flow dont les volumes représentent une heure.
    # les dates sont des chaine de caracteres
    @dir == flow.dir &&
        @type_flow == flow.type_flow &&
        @policy == flow.policy &&
        @label == flow.label &&
        @ext == flow.ext &&
        (Date.parse(@date) == Date.parse(flow.date) && @vol.to_i < flow.vol.to_i) || Date.parse(@date) < Date.parse(flow.date)
  end

  def >(flow)
    # est utilisé pour ordonner les flow dans le temps
    # ne DOIT etre utilisé que pour les flow dont les volumes représentent une heure.
    # les dates sont des chaine de caracteres
    @dir == flow.dir &&
        @type_flow == flow.type_flow &&
        @policy == flow.policy &&
        @label == flow.label &&
        @ext == flow.ext &&
        (Date.parse(@date) == Date.parse(flow.date) && @vol.to_i > flow.vol.to_i) || Date.parse(@date) > Date.parse(flow.date)
  end


  def !=(flow)
    !(self == flow)
  end


  def absolute_path
    File.join(@dir, basename)
  end

  def append(data)
    open("a+:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.write(data); @logger.an_event.debug "write data <#{data}> to flow <#{basename}>" if $debugging
  end

  def archive
    # archive le flow courant : deplace le fichier dans le repertoire ARCHIVE
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    FileUtils.mv(absolute_path, ARCHIVE, :force => true)
    @dir = ARCHIVE
    @logger.an_event.debug "archiving <#{basename}> to #{ARCHIVE}" if $debugging
  end


  def archive_previous
    # N'ARCHIVE PAS L'INSTANCE COURANTE
    # archive le flow ou les flows qui sont antérieurs à l'instance courante
    # en prenant en compte le multivolume
    # l'objectif est de faire le ménage dans le répertoire qui contient l'instance courante
    # le ou les flow sont déplacés dans ARCHIVE
    Flow.list(@dir, {:type_flow => @type_flow, :policy => @policy, :label => @label, :ext => @ext}).each { |flow|
      if self != flow
        flow.archive
        @logger.an_event.info "archive previous <#{flow.basename}>"
      end

    }

  end

  def basename
    basename = @type_flow + SEPARATOR + @policy + SEPARATOR + @label + SEPARATOR + @date
    basename += SEPARATOR + @vol unless @vol.nil?
    basename += @ext
    basename
  end

  def close
    @descriptor.close unless @descriptor.nil?
    @descriptor = nil
    @logger.an_event.debug "close flow <#{absolute_path}>" if $debugging
  end

  # Copie un flow origine :
  # soit vers un autre flow et il est retourné en sortie
  # soit vers un repertoire (String/Dir)et un nouveau flow est retourné qui pointe sur le nouveau fichier en sortie
  # remarque  : si le fichier cible existe, il est alors ecrasé
  def cp(to)
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?

    # un répertoire peut être soit un objet Dir,  String
    to_path = to.path if to.is_a?(Dir)
    to_path = to if to.is_a?(String)
    unless to_path.nil?
      raise FlowException, "target <#{to_path}> not a directory" if File.ftype(to_path) != "directory"
      raise FlowException, "target directory <#{to_path}> not exist" if !Dir.exist?(to_path)
    end
    # un fichier est représenté par un Flow exclusivement
    to_path = to.absolute_path if to.is_a?(Flow)

    FileUtils.cp(absolute_path, to_path)
    @logger.an_event.debug "copy flow <#{absolute_path}> to <#{to_path}>" if $debugging
    #si to est un flow alors on le retourne
    #si to est un répertoire alors on retourne un nouveau Flow qui représente le fichier cible
    to.is_a?(Flow) ? to : Flow.from_basename(to_path, basename)
  end

  def count_lines(eofline)
    # coompte le nombre de ligne d'un fichier
    # la fin de ligne est identifié par #{eofline}

    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    File.foreach(absolute_path, eofline, encoding: "BOM|UTF-8:-").inject(0) { |c| c+1 }
  end

  def delete
    File.delete(absolute_path) if exist?
    @logger.an_event.debug "delete flow <#{absolute_path}>" if exist?
  end

  def descriptor
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    open("r:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor
  end

  # creé une copie identique du flow courant dont le type flow est suffixé par -dup
  # retourne nouveau flow qui pointe sur le fichier dupliqué
  def duplicate
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    dup_flow = Flow.new(@dir, "#{@type_flow}-dup", @policy, @label, @date, @vol, @ext)
    cp(dup_flow)
  end

  def empty
    write("")
    close
  end

  def exist?
    File.exist?(absolute_path)
  end

  def foreach (eofline, &bloc)
    # parcours toutes les lignes d'un flow
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    IO.foreach(absolute_path, eofline, encoding: "BOM|UTF-8:-") { |p|
      begin
        yield(p.strip)
      rescue Exception => e
        raise FlowException, e
      end
    }
  end

  def get(ip_from, port_from, user, pwd)
    begin
      ftp = Net::FTP.new
      ftp.connect(ip_from, port_from)
      ftp.login(user, pwd)
      ftp.gettextfile(basename, absolute_path)
      ftp.delete(basename)
      ftp.close
      @logger.an_event.debug "get flow <#{basename}> from #{ip_from}:#{port_from}" if $debugging
    rescue Exception => e
      @logger.an_event.error "cannnot get flow <#{basename}> from #{ip_from}:#{port_from}"
      @logger.an_event.debug e if $debugging
      raise FlowException, e.message
    end
  end

  # le fichier flow courant doit exister
  # n'est utilisable que ppo
  def last
    arr = Flow.list(@dir, {:type_flow => @type_flow, :policy => @policy, :label => @label, :ext => @ext})
    newer = arr[0]
    arr.each { |flow|
      if flow > newer
        newer = flow
      end
    }
    newer
  end

  def load_to_array(eofline, class_definition=nil)
    # class_definition est une class
    # si class_definition est nil alors on range la ligne dans le array
    # si class_definition n'est pas nil alors on range une instance de la class construite à partir de la ligne, dans le array
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    raise FlowException, "eofline not define" if eofline.nil?
    array = []
    p = ProgressBar.create(:title => "Loading #{basename} file", :length => PROGRESS_BAR_SIZE, :starting_at => 0, :total => total_lines(eofline), :format => '%t, %c/%C, %a|%w|')
    volumes.each { |flow|
      IO.foreach(flow.absolute_path, eofline, encoding: "BOM|UTF-8:-") { |line|
        line = line.strip
        array << class_definition.new(line) unless class_definition.nil?
        array << line if class_definition.nil?
        p.increment
      }
    }
    close
    array
  end

  def load_to_hash(eofline)
    # class_definition est une class
    # si class_definition est nil alors on range la ligne dans le array
    # si class_definition n'est pas nil alors on range une instance de la class construite à partir de la ligne, dans le array
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    raise FlowException, "eofline not define" if eofline.nil?
    hsh = {}

    p = ProgressBar.create(:title => "Loading #{basename} file", :length => PROGRESS_BAR_SIZE, :starting_at => 0, :total => total_lines(eofline), :format => '%t, %c/%C, %a|%w|')
    volumes.each { |flow|
      IO.foreach(flow.absolute_path, eofline, encoding: "BOM|UTF-8:-") { |line|
        hsh.merge!(yield(line.chomp))
        p.increment
      }
    }
    close
    hsh
  end

  def move(to_path)
    raise FlowException, "target <#{to_path}> is not valid" unless File.exists?(to_path) && File.directory?(to_path)
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    FileUtils.cp(absolute_path, to_path)
    @logger.an_event.debug "copy flow <#{absolute_path}> to <#{to_path}>" if $debugging
    File.delete(absolute_path) if exist?
    @logger.an_event.debug "delete flow <#{absolute_path}>" if exist?
    @dir = to_path
  end

  def new_volume
    #cree un nouveau volume pour le flow
    raise FlowException, "Flow <#{absolute_path}> has no first volume" if @vol.nil?
    close
    Flow.new(@dir, @type_flow, @policy, @label, @date, @vol.to_i + 1, @ext)
  end


  def push(authentification_server_port,
           input_flows_server_ip,
           input_flows_server_port,
           ftp_server_port,
           vol = nil,
           last_volume = false)
    # si le flow n'a pas de volume identifié (mono-volume) alors on l'envoie vers l'input flow server
    # si le flow a un flow identifié (multi-volume) alors
    #     si un volume a été spécififé alors on pousse ce volume
    #     si aucune volume n'a été spécifié alors on pousse tous les volumes du flow

    if @vol.nil?
      # le flow n'a pas de volume => on pousse le flow vers sa destination  et last_volume= true
      begin
        push_vol(authentification_server_port,
                 input_flows_server_ip,
                 input_flows_server_port,
                 ftp_server_port,
                 true)

      rescue Exception => e
        @logger.an_event.error "cannot push flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port}"
        @logger.an_event.debug e if $debugging
        raise FlowException, "cannot push flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port} : #{e.message}"
      else

        @logger.an_event.debug "push flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port}" if $debugging

      end
    else
      # le flow a des volumes
      if vol.nil?
        # aucune vol n'est précisé donc on pousse tous les volumes en commancant du premier même si le flow courant n'est pas le premier,
        #en précisant pour le dernier le lastvolume = true
        count_volumes = volumes?
        volumes.each { |volume|
          begin
            volume.push_vol(authentification_server_port,
                            input_flows_server_ip,
                            input_flows_server_port,
                            ftp_server_port,
                            count_volumes == volume.vol.to_i)


          rescue Exception => e
            @logger.an_event.error "cannot push vol <#{volume.vol.to_i}> of flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port}"
            @logger.an_event.debug e if $debugging
            raise FlowException
          else

            @logger.an_event.debug "push vol <#{volume.vol.to_i}> of flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port}" if $debugging

          end
        }
      else
        # on pousse le volume précisé
        # si lastvolume n'est pas précisé alors = false
        @vol = vol.to_s
        raise FlowException, "volume <#{@vol}> of the flow <#{basename}> do not exist" unless exist? # on verifie que le volume passé existe
        begin
          push_vol(authentification_server_port,
                   input_flows_server_ip,
                   input_flows_server_port,
                   ftp_server_port,
                   last_volume)
        rescue Exception => e
          @logger.an_event.error "push vol <#{@vol}> of flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port} failed"
          @logger.an_event.debug e if $debugging
          raise FlowException
        else

          @logger.an_event.info "push vol <#{@vol}> of flow <#{basename}> to input_flow server #{input_flows_server_ip}:#{input_flows_server_port}" if $debugging

        end
      end
    end
  end

  def push_vol(authentification_server_port,
               input_flows_server_ip,
               input_flows_server_port,
               ftp_server_port,
               last_volume = false)
    #pousse un volume vers un input flow server en applicquant le sécurité
    begin
      authen = Authentification.get_one(authentification_server_port)
      @logger.an_event.info "ask a new authentification"
    rescue Exception => e
      @logger.an_event.error "cannot ask a new authentification to localhost:#{authentification_server_port} : #{e.message}"
      @logger.an_event.debug e if $debugging
      raise FlowException
    else
      @logger.an_event.info "ask a new authentification"
    end
    begin
      put(input_flows_server_ip,
          input_flows_server_port,
          ftp_server_port,
          authen.user,
          authen.pwd,
          last_volume)
    rescue Exception => e
      raise FlowException
    end
  end

  def put(ip_to, port_to, port_ftp_server, user, pwd, last_volume = false)
    # informe l'input-flow server qu'il doit telecharger le flow
    data = {
        "type_flow" => @type_flow,
        "data" => {"port_ftp_server" => port_ftp_server,
                   "user" => user,
                   "pwd" => pwd,
                   "basename" => basename,
                   "last_volume" => last_volume}
    }
    begin
      Information.new(data).send_to(ip_to, port_to)
      @logger.an_event.debug "send properties flow <#{basename}> to #{ip_to}:#{port_to}" if $debugging
    rescue Exception => e
      @logger.an_event.error "cannot send properties flow <#{basename}> to #{ip_to}:#{port_to}"
      @logger.an_event.debug e if $debugging
      raise FlowException, e.message
    end
  end

  def read
    #retourne tout le contenu du fichier dans un string
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    open("r:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.read
  end

  def readline
    #retourne un ligne du fichier
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    open("r:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.readline()
  end

  def readlines(eofline)
    # retourne toutes les lignes du fichier dans un tableau
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    open("r:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.readlines(eofline)
  end

  def rename_ext(new_ext)
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    close
    absolute_path_old = absolute_path
    @ext = new_ext
    File.rename(absolute_path_old, absolute_path)
    @logger.an_event.debug "rename ext flow <#{basename}>" if $debugging
  end

  def rewind
    #retourn au debut du fichier
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    open("r:UTF-8") if @descriptor.nil?
    @descriptor.rewind
    @logger.an_event.debug "rewind flow <#{basename}>" if $debugging
  end

  def size
    #retourne la taille du fichier
    open("r:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.size
  end

  # est utilisé pour trier le fichier contenant le details des pages html : EXCLUSIVEMENT
  # car la clé de tri n'est pas paramètrable
  #def sort(separator)
  #  raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
  #  close unless @descriptor.nil?
  #  data = Kernel.open(absolute_path)
  #  output_lines = data.lines.sort_by { |line| [line.split(separator)[1], line.split(separator)[2]] }
  #  Kernel.open(absolute_path,"w") { |f| f.write(output_lines.join) }
  #  @logger.an_event.info "sorting <#{basename}>"
  #end


  def sort (&bloc)
    # est utilisé les lignes d'un fichier
    # le tri est realisé par un bloc qui doit être passé à sort
    # exemple : un_flow.sort { |line| [line.split(";")[1], line.split(";")[2]] }

    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    close unless @descriptor.nil?
    data = Kernel.open(absolute_path)
    output_lines = data.lines.sort_by { |line| yield(line) }
    Kernel.open(absolute_path, "w") { |f| f.write(output_lines.join) }
    @logger.an_event.info "sorting <#{basename}>"
  end

  def total_lines(eofline)
    #retourne le nombre de ligne de tous les volumes du flow
    total_lines = 0
    volumes.each { |flow| total_lines += flow.count_lines(eofline) }
    total_lines
  end

  def volumes
    #renvoi un array contenant les flow de tous les volumes
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    return [self] if @vol.nil? # si le flow n'a pas de volume alors renvoi un tableau avec le flow
    array = []
    crt = self
    vol = 1
    crt.vol = vol
    while crt.exist?
      array << crt
      crt = Flow.from_absolute_path(crt.absolute_path)
      vol += 1
      crt.vol = vol
    end
    array
  end

  def volumes?
    #renvoi le nombre de volume
    raise FlowException, "Flow <#{absolute_path}> not exist" unless exist?
    return 0 if @vol.nil? # si le flow n'a pas de volume alors renvoi 0
    count = 0
    crt = self
    vol = 1
    crt.vol = vol
    while crt.exist?
      count += 1
      crt = Flow.from_absolute_path(crt.absolute_path)
      vol += 1
      crt.vol = vol
    end
    count
  end

  def vol=(vol)
    @vol = vol.to_s
  end

  def volume_exist?(vol)
    # verifie l'existence d'un volume du flow sur le disque
    Flow.new(@dir, @type_flow, @policy, @label, @date, vol, @ext).exist?
  end

  def volumes_exist?
    # verifie que tous les volumes (>=1) du flow existent sur le disque
    exist = true
    volumes.each { |vol| exist = exist && vol.exist? }
    exist
  end

  def write(data)
    open("w+:BOM|UTF-8:-") if @descriptor.nil?
    @descriptor.write(data); @logger.an_event.debug "write data <#{data}> to flow <#{basename}>" if $debugging
  end

  def zero?
    #retoune vrai si le fichier existe et a une taille de zero
    File.zero?(absolute_path)
  end

  #---------------------------------------------------------------------------------------------
  # private
  #---------------------------------------------------------------------------------------------
  private
  def open(option)
    @descriptor = File.open(absolute_path, option); @logger.an_event.debug "open <#{option}> flow <#{absolute_path}>" if $debugging
    @descriptor.sync = true
  end

end

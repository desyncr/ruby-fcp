# The simple interface to FCP from ruby
# Implements raw fcp packets with sane defaults and automates some task

require 'digest'
require 'base64'
require 'ruby-fcp/communicator'

class FCPClient < Communicator

  # Simple attribute reader for you ConnectionIdentifier
  def identifier
    @ConnectionIdentifier
  end

  # return last response from request defined by Identifier
  def last_response(id)
    @responses[id].last
  end

  # Simple interface to put a single file onto freenet from your disk uses ClientPut message
  # ==Possible values of uri:
  # * CHK@ will generate and return the key your data is acessible at
  # * SSK@ must have insert key provided by GenerateSSK or the method new_ssk_pair
  # * KSK@filename
  def simple_put(uri, filename, wait = true, opts = {})
    id = @utils.id_generate
    options = { "URI" => uri, "Identifier" => id, "UploadFrom" => 'disk', "Filename" => filename, "FileHash" => @utils.filehash_maker(id, filename,identifier), "Verbosity" => "111111111" }.merge(opts)
    options["TargetFilename"] = filename.split(File::SEPARATOR)[-1] if uri =~ /CHK@/
    send_packet @utils.packet_mangler(options,"ClientPut")
    #@com.fcpackets.client_put uri, id, options
    if wait
      wait_for id, /PutFailed|PutSuccessful/
    else
      id
    end
  end

  # Another interface to ClientPut that allows you to directly put data pnto freenet
  # data is your data
  # ==Possible values of uri:
  # * CHK@ will generate and return the key your data is acessible at
  # * SSK@ must have insert key provided by  GenerateSSK or the method new_ssk_pair
  # * KSK@filename
  def direct_put(uri,data, wait = true, opts = {})
    id = @utils.id_generate
    options = {"Identifier" => id, "URI" => uri ,"UploadFrom" =>  "direct", "DataLength" => data.bytesize }.merge(opts)
    send_packet @utils.packet_mangler(options,"ClientPut").sub! "EndMessage\n", "Data\n#{data}"
    if wait
      wait_for id,/PutFailed|PutSuccessful/
    else
      id
    end
  end

  # Simple directory upload, upload one directory all at once
  # automates the TestDDA for you just provide uri and directory
  # Implements ClientPutDiskDir
  # * CHK@ will generate and return the key your data is acessible at
  # * SSK@ must have insert key provided by  GenerateSSK or the method new_ssk_pair
  # * KSK@filename
  def simple_dir_put(uri, dir, wait = true, opts={})
    id = @utils.id_generate
    ddarun(dir,true,false)
    options = {"Identifier" => id,"URI" => uri,"Filename" => dir, "Global" => 'true', "AllowUnreadableFiles" => 'true', "IncludeHiddenValues" => 'false'}.merge(opts)
    send_packet @utils.packet_mangler(options,"ClientPutDiskDir")
    if wait
      wait_for(id,/PutFailed|PutSuccessful/)
    else
      id
    end
  end

  # simpler staight forward interface to ClientPutComplexDir, you provide with
  # ==Possible values of uri:
  # * CHK@ will generate and return the key your data is acessible at
  # * SSK@ must have insert key provided by  GenerateSSK or the method new_ssk_pair
  # * KSK@filename
  # As well as a list of hashes for files you want to put
  # ==File hashlist format:
  # * name: lib/hello or index.html, / will interperate as directory nesting
  # * filename: in case of disk location of file on disk
  # * uploadfrom: 'direct', 'disk' or 'redirect'
  # * targeturi: in case of redirect, the location your are redirecting to
  # * mimetype: not needed, but can be helpful
  # * data: only nessecery in direct mode
  def put_complex_dir(uri, files, wait = true,opts = {})
    dirs = []
    id = @utils.id_generate
    files.each{ |f| dirs << f[:filename].split(File::SEPARATOR)[0...-1].join(File::SEPARATOR) + File::SEPARATOR if f.has_key? :filename }
    (dirs.uniq).each { |dir| ddarun(dir,true,false) }
    options = {"URI" => uri, "Identifier" => id}.merge(opts)
    files.each_with_index do |file, index|
      options["Files.#{index}.Name"] = file[:name]
      options["Files.#{index}.UploadFrom"] = file[:uploadfrom]
      options["Files.#{index}.DataLength"] = file[:data].bytesize if file.has_key? :data
      options["Files.#{index}.Filename"] = file[:filename] if file[:uploadfrom].include? 'disk'
      options["Files.#{index}.TargetURI"] = file[:targeturi] if file[:uploadfrom].include? 'redirect'
      options["Files.#{index}.Metadata.ContentType"] = file[:mimetype] if file.has_key? :mimetype
    end
    message = @utils.packet_mangler(options,"ClientPutComplexDir")
    files.each { |f| message << f[:data] if f.has_key? :data}
    puts message
    send_packet message
    if wait
     wait_for(id,/PutFailed|PutSuccessful/)
    else
     id
    end
  end

  # performs TestDDARequest and TestDDAResponse automagically
  # read and write are true or false values
  def ddarun(directory,read, write)
    send_packet @utils.packet_mangler({"Directory" => directory,"WantReadDirectory" => read, "WantWriteDirectory" => write} ,"TestDDARequest")
    res = wait_for(:dda, /TestDDAReply/).pop
    content = nil
    if write
      f = File.open(res["WriteFilename"],'w+')
      f.write res["ContentToWrite"]
      f.close
    elsif read
      content = File.open(res["ReadFilename"],'r').read
    end
    send_packet @utils.packet_mangler({"Directory" => directory,"ReadContent" => content}, "TestDDAResponse")
    response = wait_for(:dda ,/TestDDAComplete/).pop
    File.delete(res["WriteFilename"]) if write
    response
  end

  # just provide uri and download path/directory
  # Implements ClientGet
  def simple_get(uri,directory,wait = true, opts={})
    id = @utils.id_generate
    saveloc = File.join directory, uri.split('/')[-1]
    ddarun(directory,false, true)
    options = {"URI" => uri, "Identifier" => id, "ReturnType" => 'disk', "Filename" => saveloc, "TempFilename" => saveloc+".tmp" , "Persistence" => 'forever', "Global" => false, "Verbosity" => 1111111}.merge(opts)
    send_packet @utils.packet_mangler(options,"ClientGet")
    if wait
     wait_for(id,/GetFailed|DataFound/)
    else
     id
    end
  end

  def direct_get(uri ,wait = true, opts={})
    id = @utils.id_generate
    options = {"URI" => uri, "Identifier" => id, "ReturnType" => 'direct', "Global" => false}.merge(opts)
    send_packet @utils.packet_mangler(options,"ClientGet")
    if wait
     wait_for(id,/AllData|GetFailed/)
    else
     id
    end
  end
  # returns information on plugin, must be full class name as listed in freenet interface
  # Implements GetPluginInfo
  def get_plugin_info(pluginname, detailed = false)
    id = @utils.id_generate
    send_packet @utils.packet_mangler({"PluginName" => pluginname, "Identifier" => id, "Detailed" => detailed },"GetPluginInfo")
    wait_for id, /PluginInfo/
  end

  # Straigt forward, ListPeers, sometimes it may choke up and give you end list peers before your peers, in that case check the id
  def listpeers
    id = @utils.id_generate
    send_packet @utils.packet_mangler({"Identifier" => id, "WithMetaData" => true, "WithVolatile" => false},"ListPeers")
    wait_for id, /EndListPeers/
  end

  #Uses GenerateSSK
  def new_ssk_pair
    id = @utils.id_generate
    send_packet @utils.packet_mangler({"Identifier" => id}, "GenerateSSK")
    wait_for id, /SSKKeypair/
  end

  # returns information on a given peer not peers implements ListPeer
  def peerinfo(peer)
    send_packet @utils.packet_mangler({"NodeIdentifier" => peer,"WithVolatile" => false,"WithMetadata" => true}, "ListPeer")
    wait_for :peer, /Peer/
  end

  # List all persistent request just implements ListPersistentRequest
  def list_persistent_requests
    send_packet "ListPersistentRequests\nEndMessage\n"
    wait_for :default ,/EndListPersistentRequests/
  end

  def modify_persistent_request(id,clienttoken,priorityclass)
    send_packet @utils.packet_mangler({"Identifier" => id,"ClientToken" => clienttoken, "PriorityClass" => priorityclass}, "ModifyPersistentRequest")
    wait_for id, /PersistentRequestModified/
  end

  #subscirbe to a usk, have to poll it yourself by using responses[id]
  def subscribe_usk(uri, wait = false ,opts ={})
    id = @utils.id_generate
    send_packet @utils.packet_mangler({"URI" => uri, "Identifier" => id} ,"SubscribeUSK")
    id
  end

  def usks_latest(uri)
    id = subscribe_usk(uri)
    response = (wait_for id, /SubscribedUSKUpdate/).pop
    unsubscribe_usk(id)
    response["Edition"].to_i
  end

  def unsubscribe_usk(id)
    send_packet "UnsubscribeUSK\nIdentifier=#{id}\nEndMessage\n"
    id
  end

  def proberequest(type,hopstolive=25,wait = true)
    id = @utils.id_generate
    send_packet @utils.packet_mangler({"Identifier" => id,"Type" => type,"HopsToLive" => hopstolive}, "ProbeRequest")
    if wait
      wait_for id,/Probe/
    else
     id
    end
  end

  # Waits for a specific pattern in a message identified by ID
  def wait_for(id, pattern)
    response = [ ]
    loop do
      begin
      x = @responses[id].pop
      print @responses[:error].pop
      rescue
      sleep(2)
      end
      unless x.nil?
        if x[:head] =~ pattern
          response << x
          x.each { |key, value| puts "#{key}=#{value}" }
          break
        elsif x[:head] =~ /ProtocolError/
          response << x
          x.each { |key, value| puts "#{key}=#{value}" }
          break
        else
          response << x
          x.each { |key, value| puts "#{key}=#{value}" }
        end
      else
        sleep(1)
      end
    end
    response
  end

  # Just wait and wait given a id
  def wait_for_ever(id)
    loop do
      begin
        x = @responses[id].pop
      rescue
        print '.'
        sleep(2)
        print @responses[:error]
        print @responses[:default]
      end
      unless x.nil?
        x.each { |key, value| puts "#{key}=#{value}" }
      else
        print '.'
        sleep(1)
        puts @responses[:error]
        print @responses[:default]
      end
    end
  end

  def killswitch
    send_packet "Shutdown\nEndMessage\n"
  end
end

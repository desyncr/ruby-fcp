require 'socket'
require 'thread'
require 'ruby-fcp/utils'

class Communicator
  attr_reader   :ConnectionIdentifier
  attr_accessor :responses, :heartbeat, :utils

  # clients name must be unique
  # This performs NodeHello operations upon initialization.
  # Communicator handles packet sending and recieving and sorting
  def initialize(client, host='127.0.0.1', port=9481, version = 2.0)
    @version = version
    @ConnectionIdentifier = ""
    @host = host
    @port = port
    @client = client
    @responses = { peers: [],dda: [], default: [], error: [], datalengths: {} }
    @tex = Mutex.new
    @state = false
    @queue = Queue.new
    @heartbeat = 300
    @utils = Utils.new
    connect
  end

  def connect
    @sock = TCPSocket.new @host ,@port
    @sock.write @utils.packet_mangler({"Name" => @client,"ExpectedVersion" => @version},"ClientHello")
    response = grab_response
    unless response[:state] == -1
      @sock_thrd = Thread.new {sock_thrd}
      @ConnectionIdentifier = response["ConnectionIdentifier"]
      @state = true
      keep_alive
    end
  end

  def sock_thrd
    @threads = []
    loop do
      @threads.each do |thrd|
        begin
          @threads.delete thrd if thrd.join(0.5)
        rescue RequestFinished => req
          @responses[:error].push req
        rescue Exception => excpt
          puts "#{excpt}"
          @threads.delete thrd
        end
        if thrd.status == false
          @threads.delete thrd
        elsif thrd.status == nil
          @threads.delete thrd
        end
      end

      @sock.close Thread.exit if @state == false

      begin
        while packet = @queue.pop(true)
          @tex.synchronize{@sock.write packet}
          #sort_out(packet)
        end
      rescue ThreadError => err
      end

      begin
        if select([@sock], nil,nil,2)
          packet = @tex.synchronize{grab_response}
          sort_out(packet)
        end
      rescue
        @sock.close Thread.exit
        state = false
        connect
      end
    end
  end

  def sort_out(packet)
    if packet[:head].include? "NodeHello"
      @ConnectionIdentifier = packet["ConnectionIdentifier"]
    elsif packet[:head].include? "CloseConnectionDuplicateClientName"
      @state = false
    elsif packet.has_key? "Identifier"
      if @responses.has_key? packet["Identifier"]
        @responses[packet["Identifier"]].push packet
      else
        @responses[packet["Identifier"]] = [packet]
      end
    elsif packet[:head].include? "DDA"
      @responses[:dda].push packet
    elsif packet[:state] == -1
      @responses[:error].push packet
    elsif packet[:head].include? "Peer"
      @responses[:peers].push packet
    else packet
      @responses[:default].push packet
    end
  end

  def send_packet(message)
    @queue.push message
  end

  def grab_response
    response = { state: 1 }
    line = @sock.readline
    response[:state] = -1 if line =~ /ClosedConnectionDuplicateClientName|ProtocolError/
    response[:head] = line.chomp
    until line =~ /EndMessage|^Data$/
      response[line.split('=')[0]] = line.split('=')[1].chomp if line.split('=').size == 2
      line = @sock.readline
    end
    @responses[:datalengths][response["Identifier"]] = response["DataLength"].to_i if response.has_key? "DataLength"
    response[:data] = @sock.read @responses[:datalengths][response["Identifier"]] if response[:head] =~ /AllData/
    response
  end

  def keep_alive
    Thread.start do
      loop do
       send_packet "Void\nEndMessage\n"
       sleep @heartbeat
       break if @state == false
      end
    end
  end

  # Send disconnect message and close the socket
  def close
    @tex.synchronize{@sock.write "Disconnect EndMessage\n"}
    @sock.close
  end

end

require 'rack'
require 'json'
require 'ipaddr'
require 'socket'
require 'benchmark'
require 'timeout'

def query_server(ip, port)
  socket = UDPSocket.new
  socket.connect(ip, port)
  socket.send("\\status\\", 0)

  data = nil
  # TODO: check if all data are received
  bench = Benchmark.measure do
    Timeout::timeout(2) do
      data, _ = socket.recvfrom(4096)
    end
  end

  # encode strange player/server names
  data = data.encode('utf-8', invalid: :replace, undef: :replace)

  data = data.split("\\")
  data.delete_at(0)
  raw_data = data[0..data.index("final")-1].each_slice(2).to_a.to_h
  raw_data['players'] = []
  raw_data['replied_in'] = bench.real

  (0..1000).each do |i|
    break unless raw_data.keys.include?("player_#{i}")
    player = {}
    ['player', 'team', 'score', 'deaths'].each do |info|
      player[info] = raw_data.delete("#{info}_#{i}")
    end
    raw_data['players'] << player
  end

  raw_data
end

class App
  HEADERS = {
    'Access-Control-Allow-Origin' => '*',
    'Content-Type' => 'application/json'
  }

  def call(env)
    path = env["PATH_INFO"].delete('/')
    ip, port = path.split(':')
    address = IPAddr.new(ip)
    port = Integer(port) + 1

    result = query_server(ip, port)

    [200, HEADERS, [result.to_json]]
  rescue IPAddr::InvalidAddressError, ArgumentError
    [400, HEADERS, [{'error' => 'invalid address'}.to_json]]
  rescue Timeout::Error
    [400, HEADERS, [{'error' => 'timeout'}.to_json]]
  rescue StandardError
    [500, HEADERS, [{'error' => 'server error'}.to_json]]
  end
end

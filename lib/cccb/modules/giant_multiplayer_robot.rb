require 'mechanize'
require 'chronic'

module CCCB::Core::GiantMultiplayerRobot
  extend Module::Requirements
  needs :bot, :commands

  def update_gmr_game(id)
    giant_multiplayer_robot.games[id] ||= OpenStruct.new
    debug "Checking GMR game ##{id}"
    m = Mechanize.new
    turns = m.get("http://multiplayerrobot.com/Game/GameDetailTurns?id=#{id}")
    last_turn_data = turns.search("div.turn-finished/div.turn-cell-text").to_a.first
    last_turn_text = last_turn_data.text.split(/\r\n/).reverse.join.gsub(/\s+/, ' ')
    last_turn = Chronic.parse( last_turn_text )

    giant_multiplayer_robot.games[id].updated = Time.now
    if giant_multiplayer_robot.games[id].last_turn != last_turn
      players = m.post("http://multiplayerrobot.com/Game/Details?id=#{id}")
      next_player = players.search("div.game-host/a/img").attribute("title").text

      giant_multiplayer_robot.games[id].last_turn = last_turn
      giant_multiplayer_robot.games[id].next_player = next_player
      return true
    else 
      return false
    end
  end

  def module_load
    giant_multiplayer_robot.games ||= {}
    giant_multiplayer_robot.channel_updated = Hash.new(0)
    giant_multiplayer_robot.channel_next_player = {}
    add_setting :channel, "gmr_games"
    default_setting 86400, "options", "gmr_nag_frequency"
    default_setting 60, "options", "gmr_update_frequency"
  end

  def module_unload
    giant_multiplayer_robot.thread.kill
  end

  def module_start
    giant_multiplayer_robot.thread = Thread.new do 
      loop do
        networking.networks.each do |name,network|
          spam "Checking GMR games on #{name}"
          network.channels.each do |ch_name, channel|
            giant_multiplayer_robot.channel_updated[channel] ||= Chronic.parse("Jan 01 1970 00:00:00 GMT")
            spam "Checking on #{channel}"
            begin
              channel.get_setting("gmr_games").each do |game_name, game_id|
                spam "Check GMR: #{channel} #{game_name}"
                game = giant_multiplayer_robot.games[game_id]
                frequency = channel.get_setting("options", "gmr_update_frequency").to_i
                if game.nil? or Time.now - game.updated  > frequency
                  debug "Update GMR #{channel} #{game_name}/#{game_id} #{Time.now - game.updated } > #{frequency}"
                  update_gmr_game(game_id)
                  game = giant_multiplayer_robot.games[game_id]
                end

                channel_elapsed = Time.now - giant_multiplayer_robot.channel_updated[channel]

                next_player_map = (giant_multiplayer_robot.channel_next_player[channel] ||= {})

                if next_player_map[game_id].nil? or next_player_map[game_id] != game.next_player or 
                  (Time.now - giant_multiplayer_robot.channel_updated[channel]) > channel.get_setting("options","gmr_nag_frequency").to_i
                then
                  waiting = elapsed_time( Time.now - game.last_turn )
                  channel.msg "GMR Game #{game_name} (##{game_id}): Next player is #{game.next_player}. Waiting #{waiting}"
                  giant_multiplayer_robot.channel_updated[channel] = Time.now
                  next_player_map[game_id] = game.next_player
                end
              end
            rescue Exception => e
              critical "Exception in GMR thread: #{e} #{e.backtrace}"
            end
          end
        end
        sleep 1
      end
    end
  end

end

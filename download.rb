require 'nokogiri'
require 'open-uri'
require 'active_record'

db_config = YAML::load(File.open(File.join(File.dirname(__FILE__),'config','database.yml')))['development']
ActiveRecord::Base.establish_connection(db_config)

POSITIONS = {
  1 => 'QB',
  2 => 'RB',
  3 => 'WR',
  4 => 'TE',
  7 => 'K',
  8 => 'DEF'
}

PAGES = {
  1 => 6,
  2 => 9,
  3 => 9,
  4 => 7,
  7 => 3,
  8 => 2
}

DRAFT_COUNTS = {
  'QB' => 1,
  'RB' => 2,
  'WR' => 3,
  'TE' => 1,
  'K' => 1,
  'DEF' => 1
}

class Player < ActiveRecord::Base
  def to_line
    "#{name}||#{position}||#{points}\n"
  end
end

class Downloader
  def self.download
    POSITIONS.each do |id, position|
      (1..PAGES[id]).each do |page|
        offset = ((page - 1) * 25) + 1
        url = "http://fantasy.nfl.com/research/scoringleaders?offset=#{offset}&position=#{id}&sort=pts&statCategory=stats&statSeason=2011&statType=seasonStats&statWeek=1"
        puts "Retrieving #{position} page #{page} at #{url}"

        doc = Nokogiri::HTML(open(url))

        player_info = doc.at_css('table.tableType-player tbody')

        player_info.css('tr').each do |row|
          name = row.at_css('.playerNameAndInfo a').content
          points = row.at_css('.statTotal').content.to_f
          player = Player.new(name, position, points)

          File.open("#{position}.text", 'a') do |f|
            f.write(player.to_s)
          end
        end
      end
    end
  end
end

class App
  def self.ingest
    POSITIONS.values.each do |position|
      lines = File.readlines("#{position}.text").collect(&:chomp)

      lines.each do |line|
        name, player_position, points = line.split('||')
        p = Player.new(:name => name, :position => player_position, :points => points.to_f)
        p.save
      end
    end
  end

  def self.print_standard_deviations
    POSITIONS.values.each do |position|
      puts "Evaluating: #{position}"
      players = Player.find_all_by_position(position)

      sum = players.collect{|p| p.points}.inject(0){|accum, i| accum + i}
      # puts "Sum for #{position}: #{sum}"

      mean = sum / players.length
      # puts "Mean for #{position}: #{mean}"

      sample_variance_sum = players.collect{|p| p.points}.inject(0){|accum, i| accum + (i - mean) ** 2 }
      sample_variance = sum / (players.length - 1).to_f
      # puts "Sample Variance for #{position}: #{sample_variance}"

      standard_deviation = Math.sqrt(sample_variance)
      # puts "Standard Deviation for #{position}: #{standard_deviation}"
      puts "  Standard Deviation: #{standard_deviation}"

      max = Player.where(:position => position).maximum(:points)
      puts "  Highest score:      #{max}"
      # puts "Max: #{max}"

      (1..30).each do |rank|
        players = Player.where(:position => position).where(:points => ((max - (rank * standard_deviation))..((max - (rank - 1) * standard_deviation)))).all

        puts "  Choice #{rank}"
        players.each do |player|
          puts "    #{player.name}"
        end
      end
    end
  end

  def self.picker(positions)
    team = Hash.new{|h,k| h[k] = []}

    Player.where(:drafted => false).where(:position => positions).all.each do |player|
      # Sort the current scores
      team[player.position].sort!

      # If there are open spots left
      if team[player.position].length < DRAFT_COUNTS[player.position]
        team[player.position] << player.points.to_f
      elsif team[player.position].sort.first < player.points
        team[player.position][0] = player.points
      end
    end

    team.each do |position, scores|
      puts "At #{position}:"
      scores.each do |score|
        player = Player.find_by_position_and_points(position, score)
        puts "  #{player.name}"
      end
    end
    puts "Total score: #{team.values.flatten.inject(:+)}"
  end

  def self.next(positions, places_between)
    positions = positions.split(',')
    differences = {}

    positions.each do |position|
      players = Player.where(:position => position).where(:drafted => false).order('points desc').limit(places_between.to_i).all

      players.sort!{|x,y| x.points <=> y.points}

      difference = players.last.points - players.first.points
      differences[position] = difference.to_f

      # puts "Point difference for #{position}: #{players.last.points - players.first.points}"
    end

    # puts differences.inspect
    puts differences.sort{|x,y| y[1] <=> x[1]}.inspect
  end
end

App.next(ARGV[0], ARGV[1])
App.picker(ARGV[0].split(','))

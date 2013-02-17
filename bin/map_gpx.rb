#!/usr/bin/env ruby

require 'nokogiri'
require 'time'
require 'fileutils'
require 'rasem'
require 'pp'

AIR = 5

# from https://github.com/esmooov/svgsimplifier
class RamerDouglasPeucker

  def self.simplify(points, epsilon = 0.5)
    # Find the point with the maximum distance
    dmax = 0
    index = 0

    # If the distance is greater than epsilon, recursively simplify
    for i in 1..(points.length - 1)
      d = calculate_distance_from_line(points[0], points[-1], points[i])
      if d > dmax
        index = i
        dmax = d
      end
    end

    result = if dmax >= epsilon
      recResults1 = simplify(points[0..index], epsilon)
      recResults2 = simplify(points[index..-1], epsilon)
      [recResults1[0..-2], recResults2[0..-1]].flatten
    else
      avg_speed = points.inject(0) { |t, p| t + p.speed } / points.length
      points[-1].speed = avg_speed
      [points[0], points[-1]]
    end
    result
  end

  private

  def self.calculate_distance_from_line(a, b, p)
    normal_length = Math.hypot(b.x - a.x, b.y - a.y)
    ((p.x - a.x) * (b.y - a.y) - (p.y - a.y) * (b.x - a.x)).abs / normal_length
  end  

end

class Point
  DIST_FACTOR = 10000

  attr_accessor :x, :y, :at, :speed

  def initialize(x, y, at)
    @x = (x.to_f * DIST_FACTOR).round(2)
    @y = (y.to_f * DIST_FACTOR).round(2)
    @at = DateTime.parse(at).to_time
    @speed = 0
  end

  def speed_color(min_speed, max_speed)
    percent = (@speed - min_speed) / (max_speed - min_speed)
    if percent < 0.25
      "rgb(0,#{(255 * percent * 4).round},255)"
    elsif percent < 0.5
      "rgb(0,255,#{(255 * (1 - percent) * 4).round})"
    elsif percent < 0.75
      "rgb(#{(255 * percent * 4).round},255,0)"
    else
      "rgb(255,#{(255 * (1 - percent) * 4).round},0)"
    end
  end
end

class Track
  SPEED_FACTOR = 100

  attr_accessor :filename, :points, :min_speed, :max_speed, :min_x, :max_x, :min_y, :max_y

  def initialize(gpx_file)
    @filename = gpx_file
    puts "  Parsing #{gpx_file}"
    @points = RamerDouglasPeucker.simplify(parse_gpx(@filename))
    puts "    Computing track limits"
    set_min_max_pos
    puts "    Computing speed"
    compute_speed
    puts "    Computing speed limits"
    set_min_max_speed
  end

  def translate(min_x, min_y)
    @min_x = @min_x - min_x
    @max_x = @max_x - min_x
    @min_y = @min_y - min_y
    @max_y = @max_y - min_y
    @points.each do |point|
      point.x = point.x - min_x
      point.y = point.y - min_y
    end
  end

  def invert_y(max_y)
    @points.each do |point|
      point.y = max_y - point.y
    end
  end

  private

  def parse_gpx(gpx_file)
    gpx_doc = Nokogiri::XML.parse(File.open(gpx_file))
    gpx_doc.remove_namespaces!
    gpx_doc.xpath('/gpx/trk/trkseg/trkpt').map do |gpx_point|
      Point.new(gpx_point.attribute('lon').content, gpx_point.attribute('lat').content, gpx_point.at_xpath('time').content)
    end
  end

  def set_min_max_pos
    @points.each do |point|
      @min_x = point.x if @min_x.nil? or point.x < @min_x
      @max_x = point.x if @max_x.nil? or point.x > @max_x
      @min_y = point.y if @min_y.nil? or point.y < @min_y
      @max_y = point.y if @max_y.nil? or point.y > @max_y
    end
  end

  def compute_speed
    @points.each_index do |index|
      if index > 0
        dist = Math.sqrt((points[index - 1].x - points[index].x)**2 + (points[index - 1].y - points[index].y)**2)
        time = points[index].at - points[index - 1].at
        points[index].speed = dist / time * SPEED_FACTOR if time > 0
      end
    end
  end

  def set_min_max_speed
    @points.each do |point|
      @min_speed = point.speed if @min_speed.nil? or point.speed < @min_speed
      @max_speed = point.speed if @max_speed.nil? or point.speed > @max_speed
    end
  end
end

def get_min_max_pos(min_max, tracks)
  tracks.each do |track|
    min_max[:min_x] = track.min_x if min_max[:min_x].nil? or track.min_x < min_max[:min_x]
    min_max[:max_x] = track.max_x if min_max[:max_x].nil? or track.max_x > min_max[:max_x]
    min_max[:min_y] = track.min_y if min_max[:min_y].nil? or track.min_y < min_max[:min_y]
    min_max[:max_y] = track.max_y if min_max[:max_y].nil? or track.max_y > min_max[:max_y]
  end
end

def translate(min_max, tracks)
  min_x = min_max[:min_x]
  min_max[:min_x] = 0
  min_max[:max_x] = min_max[:max_x] - min_x
  min_y = min_max[:min_y]
  min_max[:min_y] = 0
  min_max[:max_y] = min_max[:max_y] - min_y
  tracks.each do |track|
    track.translate min_x, min_y
  end
  # invert all y, else drawing is top <-> bottom
  max_y = 0
  tracks.each do |track|
    max_y = track.max_y if track.max_y > max_y
  end
  tracks.each do |track|
    track.invert_y max_y
  end
end

def get_min_max_speed(min_max, tracks)
  tracks.each do |track|
    min_max[:min_speed] = track.min_speed if min_max[:min_speed].nil? or track.min_speed < min_max[:min_speed]
    min_max[:max_speed] = track.max_speed if min_max[:max_speed].nil? or track.max_speed > min_max[:max_speed]
  end
end

def generate_svg(min_max, tracks)
  FileUtils.mkdir_p('svg')
  File.open("svg/graph_test.svg", 'w') do |svg_file|
    Rasem::SVGImage.new(min_max[:max_x].round(2) + 2 * AIR, min_max[:max_y].round(2) + 2 * AIR, svg_file) do |image|
      tracks.each do |track|
        track.points.each_index do |index|
          if index > 0
            line track.points[index - 1].x.round(2) + AIR, track.points[index - 1].y.round(2) + AIR,
                 track.points[index].x.round(2) + AIR, track.points[index].y.round(2) + AIR,
                 'stroke' => track.points[index].speed_color(track.min_speed, track.max_speed),
                 'stroke-width' => 3,
                 'stroke-opacity' => (1.0 / tracks.length)
          end
        end
      end
    end
  end
end

puts "Mapping GPX files to SVG"

tracks = []

puts "Parsing files"
Dir['gpx/*.gpx'].each do |gpx_file|
  tracks << Track.new(gpx_file)
end

min_max = { :min_x => nil,
            :max_x => nil,
            :min_y => nil,
            :max_y => nil,
            :min_speed => nil,
            :max_speed => nil }

puts "Computing drawing limits"
get_min_max_pos min_max, tracks

puts "Normalizing"
translate min_max, tracks

puts "Computing speed limits"
get_min_max_speed min_max, tracks

puts "Rendering"
generate_svg min_max, tracks

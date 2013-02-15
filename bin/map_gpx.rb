#!/usr/bin/env ruby

require 'nokogiri'
require 'time'
require 'fileutils'
require 'rasem'
require 'pp'

DIST_FACTOR = 10000
SPEED_FACTOR = 100

class Point
  attr_accessor :lat, :lon, :at, :speed

  def initialize(lat, lon, at)
    @lat = lat.to_f
    @lon = lon.to_f
    @at = DateTime.parse(at).to_time
    @speed = 0
  end
end

def parse_gpx(gpx_file)
  gpx_doc = Nokogiri::XML.parse(File.open(gpx_file))
  gpx_doc.remove_namespaces!
  gpx_doc.xpath('/gpx/trk/trkseg/trkpt').map do |gpx_point|
    Point.new(gpx_point.attribute('lat').content, gpx_point.attribute('lon').content, gpx_point.at_xpath('time').content)
  end
end

def get_min_max(points)
  min_max = { :lat => { :min => nil,
                        :max => nil },
              :lon => { :min => nil,
                        :max => nil } }
  points.each_with_index do |point, index|
    if index == 0
      min_max[:lat][:min] = point.lat
      min_max[:lat][:max] = point.lat
      min_max[:lon][:min] = point.lon
      min_max[:lon][:max] = point.lon
    else
      min_max[:lat][:min] = point.lat if point.lat < min_max[:lat][:min]
      min_max[:lat][:max] = point.lat if point.lat > min_max[:lat][:max]
      min_max[:lon][:min] = point.lon if point.lon < min_max[:lon][:min]
      min_max[:lon][:max] = point.lon if point.lon > min_max[:lon][:max]
    end
  end
  min_max
end

def translate(min_max, points)
  min_lat = min_max[:lat][:min]
  min_max[:lat][:min] = 0
  min_max[:lat][:max] = (min_max[:lat][:max] - min_lat) * DIST_FACTOR
  min_lon = min_max[:lon][:min]
  min_max[:lon][:min] = 0
  min_max[:lon][:max] = (min_max[:lon][:max] - min_lon) * DIST_FACTOR
  points.each do |point|
    point.lat = (point.lat - min_lat) * DIST_FACTOR
    point.lon = (point.lon - min_lon) * DIST_FACTOR
  end
  # invert all lat, else drawing is top <-> bottom
  max_lat = 0
  points.each do |point|
    max_lat = point.lat if point.lat > max_lat
  end
  points.each do |point|
    point.lat = max_lat - point.lat
  end
end

def compute_speed(points)
  points.each_index do |index|
    if index > 0
      dist = Math.sqrt((points[index - 1].lon - points[index].lon)**2 + (points[index - 1].lat - points[index].lat)**2)
      time = points[index].at - points[index - 1].at
      points[index].speed = dist / time * SPEED_FACTOR if time > 0
    end
  end
end

def get_min_max_speed(min_max, points)
  min_max[:speed] ||= {}
  points.each_with_index do |point, index|
    if index == 0
      min_max[:speed][:min] = point.speed
      min_max[:speed][:max] = point.speed
    else
      min_max[:speed][:min] = point.speed if point.speed < min_max[:speed][:min]
      min_max[:speed][:max] = point.speed if point.speed > min_max[:speed][:max]
    end
  end
  min_max
end

def generate_speed_color(min_speed, max_speed, current_speed)
  percent = (current_speed - min_speed) / (max_speed - min_speed)
  if percent < 0.5
    "rgb(255,#{(255 * percent * 2).round},0)"
  else
    "rgb(#{(255 * (1 - percent * 2)).round},255,0)"
  end
end

def generate_svg(filename, points, min_max)
  FileUtils.mkdir_p('svg')
  File.open("svg/#{File.basename(filename, '.gpx')}.svg", 'w') do |svg_file|
    Rasem::SVGImage.new(min_max[:lon][:max], min_max[:lat][:max], svg_file) do |image|
      points.each_index do |index|
        if index > 0
          line points[index - 1].lon, points[index - 1].lat, points[index].lon, points[index].lat, 'stroke' => generate_speed_color(min_max[:speed][:min], min_max[:speed][:max], points[index].speed), 'stroke-width' => 3 
        end
      end
    end
  end
end

puts "Mapping GPX file to SVG"

Dir['gpx/*.gpx'].each do |gpx_file|
  puts "Analyzing #{gpx_file}"
  points = parse_gpx(gpx_file)
  min_max = get_min_max(points)
  translate(min_max, points)
  compute_speed(points)
  min_max = get_min_max_speed(min_max, points)
  generate_svg(File.basename(gpx_file), points, min_max)
end

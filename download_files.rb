require 'net/http'
require 'uri'
require 'fileutils'
require 'thread'
require 'json'

def download_file(url, output_dir, prefix, title)
  uri = URI.parse(url)
  safe_title = title.gsub(/[^0-9A-Za-z]/, '_') # Replace all non-alphanumeric characters with underscores
  filename = File.join(output_dir, "#{prefix}#{File.basename(uri.path, '.*')} - #{safe_title}#{File.extname(uri.path)}")

  if File.exist?(filename)
    puts "Skipped #{filename} (already exists)"
    return
  end

  begin
    response = Net::HTTP.get_response(uri)
    case response
    when Net::HTTPSuccess then
      File.open(filename, 'wb') { |file| file.write(response.body) }
      puts "Downloaded #{filename}"
    when Net::HTTPRedirection then
      puts "Redirected #{url} to #{response['location']}"
      download_file(response['location'], output_dir, prefix, title)
    else
      puts "Failed to download #{url}: #{response.message}"
    end
  rescue => e
    puts "Failed to download #{url}: #{e.message}"
  end
end

def download_files_from_list(file_path, output_dir, max_threads)
  urls = File.readlines(file_path).map(&:strip).reject(&:empty?)
  queue = Queue.new
  urls.each { |line| queue << line }

  threads = []
  max_threads.times do
    threads << Thread.new do
      while (line = queue.pop(true) rescue nil)
        url, prefix, title = line.split(' ', 3)
        title = title.tr('_', ' ') # Replace underscores with spaces
        puts "Processing #{url}"
        download_file(url, output_dir, prefix, title)
      end
    end
  end

  threads.each(&:join)
end

def parse_json_files(file_paths)
  download_data = []
  file_paths.each do |file_path|
    data = JSON.parse(File.read(file_path))
    data['episodes'].each do |episode|
      url = episode['download_media_url']
      episode_guid = episode['episode_guid'] ? "Epi_#{episode['episode_guid']}_" : "Epi__"
      title = episode['title'] ? episode['title'].gsub(/[^0-9A-Za-z]/, '_') : ""
      download_data << { url: url, prefix: episode_guid, title: title }
    end
  end
  download_data
end

# episodes1.json = https://www.podomatic.com/v2/podcasts/301555/episodes?per_page=100&page=1
# episodes2.json = https://www.podomatic.com/v2/podcasts/301555/episodes?per_page=100&page=2
# episodes3.json = https://www.podomatic.com/v2/podcasts/301555/episodes?per_page=100&page=3

# Set the path to the JSON files and the output directory
json_files = ['episodes1.json', 'episodes2.json', 'episodes3.json']
output_directory = './local-files'
max_threads = 10

# Parse the JSON files
download_data = parse_json_files(json_files)

# Create a temporary file to store the download URLs, prefixes, and titles
temp_file = 'download_urls_with_prefixes.txt'
File.open(temp_file, 'w') do |file|
  download_data.each do |data|
    file.puts("#{data[:url]} #{data[:prefix]} #{data[:title]}")
  end
end

# Create the output directory if it doesn't exist
FileUtils.mkdir_p(output_directory)

# Start the download process
download_files_from_list(temp_file, output_directory, max_threads)

# Remove the temporary file
File.delete(temp_file)

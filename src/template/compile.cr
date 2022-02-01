require "../template"

filename = ARGV[0]
buffer_name = ARGV[1]

STDERR.puts "Compiling template #{filename}..."
begin
  puts ::Armature::Template.process_file(filename, buffer_name)
rescue ex : File::Error
  STDERR.puts ex.message
  exit 1
end

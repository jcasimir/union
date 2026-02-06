# frozen_string_literal: true

require "yaml"

# Validates person profiles and reports missing fields
class ProfileValidator
  REQUIRED_FIELDS = {
    "name" => "Identity",
    "professional.role" => "Professional",
    "professional.organization" => "Professional",
    "meta.created_at" => "Metadata",
    "meta.updated_at" => "Metadata"
  }.freeze

  RECOMMENDED_FIELDS = {
    "email" => "Identity",
    "professional.reports_to" => "Professional",
    "professional.tenure_started" => "Professional",
    "personal.location" => "Personal",
    "personal.family.spouse" => "Personal",
    "personal.interests" => "Personal",
    "relationship.meeting_cadence" => "Relationship",
    "working_context.current_focus" => "Working Context"
  }.freeze

  PERSONAL_FIELDS = {
    "personal.location" => "Where they live",
    "personal.hometown" => "Where they're from",
    "personal.family.spouse" => "Spouse/partner",
    "personal.family.kids" => "Children",
    "personal.family.pets" => "Pets",
    "personal.education" => "Education/schools",
    "personal.interests" => "Hobbies/interests"
  }.freeze

  def initialize(profile_path)
    @profile = YAML.load_file(profile_path)
    @path = profile_path
  end

  def validate
    results = {
      name: @profile["name"],
      missing_required: [],
      missing_recommended: [],
      missing_personal: [],
      completeness: {}
    }

    REQUIRED_FIELDS.each do |field, category|
      results[:missing_required] << { field: field, category: category } if field_empty?(field)
    end

    RECOMMENDED_FIELDS.each do |field, category|
      results[:missing_recommended] << { field: field, category: category } if field_empty?(field)
    end

    PERSONAL_FIELDS.each do |field, description|
      results[:missing_personal] << { field: field, description: description } if field_empty?(field)
    end

    # Calculate completeness scores
    results[:completeness] = {
      required: percentage_complete(REQUIRED_FIELDS),
      recommended: percentage_complete(RECOMMENDED_FIELDS),
      personal: percentage_complete(PERSONAL_FIELDS),
      overall: percentage_complete(REQUIRED_FIELDS.merge(RECOMMENDED_FIELDS).merge(PERSONAL_FIELDS))
    }

    results
  end

  def report
    results = validate
    lines = []

    lines << "Profile: #{results[:name]}"
    lines << "=" * 50
    lines << ""

    # Completeness summary
    lines << "Completeness:"
    results[:completeness].each do |category, pct|
      bar = completeness_bar(pct)
      lines << "  #{category.to_s.ljust(12)} #{bar} #{pct}%"
    end
    lines << ""

    # Missing required
    if results[:missing_required].any?
      lines << "Missing REQUIRED fields:"
      results[:missing_required].each do |item|
        lines << "  - #{item[:field]}"
      end
      lines << ""
    end

    # Missing personal (the bio stuff)
    if results[:missing_personal].any?
      lines << "Missing PERSONAL details (for the bio):"
      results[:missing_personal].each do |item|
        lines << "  - #{item[:description]} (#{item[:field]})"
      end
      lines << ""
    end

    # Missing recommended
    if results[:missing_recommended].any?
      lines << "Missing recommended fields:"
      results[:missing_recommended].each do |item|
        lines << "  - #{item[:field]}"
      end
    end

    lines.join("\n")
  end

  private

  def field_empty?(field_path)
    value = dig_field(field_path)
    value.nil? || value == "" || value == [] || value == {}
  end

  def dig_field(field_path)
    keys = field_path.split(".")
    keys.reduce(@profile) do |obj, key|
      return nil unless obj.is_a?(Hash)
      obj[key]
    end
  end

  def percentage_complete(fields)
    filled = fields.keys.count { |f| !field_empty?(f) }
    ((filled.to_f / fields.size) * 100).round
  end

  def completeness_bar(pct, width = 20)
    filled = (pct / 100.0 * width).round
    empty = width - filled
    "[#{"#" * filled}#{"-" * empty}]"
  end
end

# CLI usage
if __FILE__ == $PROGRAM_NAME
  if ARGV.empty?
    puts "Usage: ruby profile_validator.rb <profile.yaml>"
    puts "       ruby profile_validator.rb --all <profiles_directory>"
    exit 1
  end

  if ARGV[0] == "--all"
    dir = ARGV[1] || File.expand_path("~/GDrive/Meeting Notes/People")
    Dir.glob(File.join(dir, "*.yaml")).each do |path|
      next if File.basename(path).start_with?("_")
      puts ProfileValidator.new(path).report
      puts "\n"
    end
  else
    puts ProfileValidator.new(ARGV[0]).report
  end
end

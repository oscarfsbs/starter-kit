#!/usr/bin/env ruby
# encoding: utf-8
# rubocop: disable MethodLength

require 'pry' # FIXME

columns = [
  ['Code', :Code__STR],
  ['DisplayName', :HTML_DisplayName__STR],
  ['Expiry Date', :"metadata_Expiry Date"],
  ['Document Type', :"metadata_Document Type"],
  ['Team', :metadata_Team],
  ['Contact', :metadata_Contact],
  ['Key Words', :Keywords__STR],
  ['Retired?', :b_IsRetired],
  ['Archived?', :b_IsArchived],
  ['Deleted?', :b_IsDeleted],
  ['Category 0', :Category0],
  ['Category 1', :Category1],
  ['Category 2', :Category2],
  ['Category 3', :Category3]
]

require 'nokogiri'
require 'csv'

# Extracts the information from the XML
class PageflexData
  attr_reader :names, :metadata, :products, :categories, :cat_entries

  def initialize
    puts 'Parsing XML document'
    @doc      = parse_xml_doc
    puts 'Extracting field names table'
    @names    = build_names
    puts 'Extracting metadata table, resolving names'
    @metadata = build_metadata
    puts 'Extracting products table'
    @products = build_products
    puts 'Extracting categories table'
    @categories = build_categories
    puts 'Extracting catalog entries table'
    @cat_entries = build_catalog_entries
  end

  private

  def parse_xml_doc
    # Get the xml location from the CLI args
    if ARGV.any?
      a_xml = File.read(ARGV.join(' '))
      doc   = Nokogiri::XML(a_xml)
    else
      abort 'Pass the location of the MMStore XML to run script'
    end
    doc
  end

  def build_names
    names = {}
    @doc.xpath(
      '/PFWeb:Database/PFWeb:Names__Table/PFWeb:Names__Row'
    ).each do |i|
      n_key   = i.attributes['NameID__ID'].value.to_sym
      n_value = i.attributes['StringValue__STR'].value
      names[n_key] = n_value
    end
    names
  end

  def build_metadata
    metadata = {}
    @doc.xpath([
      '/PFWeb:Database', '/PFWeb:ProductMetadataFieldValues__Table',
      '/PFWeb:ProductMetadataFieldValues__Row'
    ].join('')).each do |i|
      key   = i.attributes['ProductID__IDREF'].value.to_sym
      name  = @names[i.attributes['FieldNameID__IDREF'].value.to_sym]
      name  = ('metadata_' + name).to_sym
      value = i.attributes['FieldValue__STR']
      value = value ? value.value : '' # Handle nil values
      a = metadata.fetch key, {}
      a[name] = value
      metadata[key] = a
    end
    metadata
  end

  def build_products
    products = {}
    @doc.xpath(
      '/PFWeb:Database/PFWeb:Products__Table/PFWeb:Products__Row'
    ).each do |i|
      id, attrs = nil, {}
      i.attributes.each do |a|
        id    = a[1].value.to_sym if a[1].name == 'ProductID__ID'
        key   = a[0].to_sym
        value = a[1].value
        attrs[key] = value
      end
      products[id] = attrs
    end
    products
  end

  def build_categories
    categories = {}
    @doc.xpath([
      '/PFWeb:Database/PFWeb:ProductCatalogCategories__Table',
      '/PFWeb:ProductCatalogCategories__Row'
    ].join('')).each do |i|
      id, attrs = nil, {}
      i.attributes.each do |a|
        id    = a[1].value.to_sym if a[1].name == 'ProductCategoryID__ID'
        key   = a[0].to_sym
        value = a[1].value
        attrs[key] = value
      end
      categories[id] = attrs
    end
    categories
  end

  def build_catalog_entries
    entries = {}
    @doc.xpath([
      '/PFWeb:Database/PFWeb:ProductCatalogEntries__Table',
      '/PFWeb:ProductCatalogEntries__Row'
    ].join('')).each do |i|
      key   = i.attributes['ProductID__IDREF'].value.to_sym
      value = i.attributes['ParentCategoryID__IDREF'].value
      entries[key] = (entries.fetch key, []) << value
    end
    entries
  end
end

# Selects current versions of products and attaches data
class CurrentProducts < Hash
  def initialize(pf_products, pf_metadata, pf_cat_entries, categories)
    puts 'Identifying current products, adding metadata and categories'
    load_current_products pf_products, pf_cat_entries
    attach_metadata pf_metadata
    attach_categories pf_cat_entries, categories
  end

  private

  def load_current_products(pf_products, pf_cat_entries)
    pf_products.each do |p|
      self[p[0]] = p[1] if pf_cat_entries.key? p[0]
    end
  end

  def attach_metadata(metadata)
    values.each do |p|
      p.merge! metadata.fetch p[:ProductID__ID].to_sym, {}
    end
  end

  def attach_categories(pf_cat_entries, categories)
    pf_cat_entries.each do |e|
      e[1].each_with_index do |c, i|
        self[e[0]]["Category#{i}".to_sym] = categories[c.to_sym][:Path]
      end
    end
  end
end

# Builds full category path strings
class Categories < Hash
  def initialize(pf_cats)
    get_all_paths! pf_cats
  end

  private

  def get_all_paths!(cats)
    cats.each do |c|
      c[1][:Path] = get_path!(cats, c[1]) unless c[1][:Path]
      self[c[0]] = c[1]
    end
  end

  def get_path!(cats, c)
    if c[:Path]
      c[:Path]
    elsif c[:ParentCategoryID__IDREF]
      c[:Path] = [
        get_path!(cats, cats[(c[:ParentCategoryID__IDREF].to_sym)]),
        c[:DisplayName__STR]
      ].join ' > '
    else
      c[:Path] = c[:DisplayName__STR]
    end
  end
end

# Builds our report CSV
class PageflexReport < Array
  def initialize(current_products, columns)
    build_report current_products, columns
  end

  def write_csv
    file_name = "mmstore_report_#{Time.new.strftime '%Y_%m_%d'}.csv"
    puts "Writing to '#{file_name}'"
    CSV.open(file_name, 'wb') do |csv|
      each { |row| csv << row }
    end
    self
  end

  private

  def build_report(products, columns)
    products.each do |p|
      row = []
      columns.each { |c| row << (p[1].fetch c[1], '') }
      self << row
    end
    # Add header
    unshift columns.reduce([]) { |a, e| a << e[0] }
  end
end

# Report with our custom changes
class CustomPageflexReport < PageflexReport
  def initialize(current_products, columns)
    super
    shift # Remove header
    strip_html
    sort_by_uk_date
    # Add header
    unshift columns.reduce([]) { |a, e| a << e[0] }
  end

  private

  def sort_by_uk_date
    # Sort by the third column, after formatting the date to be sortable
    puts 'Sorting by date'
    sort! do |y, x|
      x[2].split('/').reverse.join('/') <=> y[2].split('/').reverse.join('/')
    end
  end

  def strip_html
    puts 'Stripping in-line HTML'
    map! { |row| row.map! { |cell| cell.sub(/ *<.*>.*<\/.*>/, '') } }
  end
end

# rubocop: disable all
a = PageflexData.new
b = Categories.new a.categories
c = CurrentProducts.new a.products, a.metadata, a.cat_entries, b
a, b = nil
CustomPageflexReport.new(c, columns).write_csv
puts "\t...done!"

class DND5eTreasure

  require 'securerandom'

  def self.roll(num, die)
    rolls = (1..num).map { SecureRandom.random_number(die) + 1 }
    total = rolls.inject(:+)
    puts "Rolled: #{num}d#{die}: #{rolls.inspect} = #{total}" if $VERBOSE
    total
  end

  TREASURE_TABLES = {
    "pouch" => {
      common: {
        (7..13) => [ "copper piece", 5, 6 ],
        (14..100) => [ "silver piece", 4, 6 ]
      },
      rare: {
        (13..14) => [ "electrum piece", 3, 6 ],
        (15..22) => [ "gold piece", 2, 6 ],
        (23..100) => [ "platinum piece", 1, 6 ]
      },
      gems_and_art: {
        (17..21) => [ "ornamental gem", 1, 6 ],
        (22..26) => [ "semiprecious gem", 1, 6 ],
        (27..31) => [ "decorative art object", 1, 3 ],
        (37..100) => [ "fine art object", 1, 1 ]
      },
      magic_items: {
        (18..23) => [ "common potion", 1, 4 ],
        (24..27) => [ "uncommon magic item", 1, 1 ],
        (28..29) => [ "rare magic item", 1, 1 ],
        (30..100) => [ "very rare magic item", 1, 1 ]
      }
    },
    "chest" => {
      copper: {
        (10..100) => [ "copper piece", 4, 8, 100 ]
      },
      silver: {
        (10..18) => [ "silver piece", 3, 8, 10 ],
        (19..100) => [ "electrum piece", 3, 8, 10 ],
      },
      gold: {
        (15..100) => [ "gold piece", 3,8,10 ],
      },
      platinum: {
        (19..100) => [ "platinum piece", 3, 8 ],
      },
      gems_and_art: {
        (17..22) => [ "ornamental gem", 2, 8 ],
        (23..27) => [ "semiprecious gem", 2, 8 ],
        (28..100) => [ "precious gem", 1, 8 ]
      },
      art: {
        (23..29) => [ "decorative art object", 1, 8 ],
        (30..100) => [ "fine art object", 1, 8 ],
      },
      magic_items: {
        (17..22) => [ "common potion", 2, 4 ],
        (23..26) => [ "uncommon magic item", 1, 4, 1, -1 ],
        (27..29) => [ "rare magic item", 1, 2 ],
        (30..32) => [ "very rare magic item", 1, 1 ],
        (33..100) => [ "legendary magic item", 1, 1 ]
      }
    }
  }

  TREASURE_DETAIL = {
    "ornamental gem" => {
      (1..20) => {
        value: [ 4, 4, 1 ],
        names: [
          "Banded Agate",
          "Moss Agate",
          "Eye Agate",
          "Azurite",
          "Bloodstone",
          "Carnelian",
          "Chalcedony",
          "Chrysoprase",
          "Citrine",
          "Haematite",
          "Iolite",
          "Jasper",
          "Lapis Lazuli",
          "Malachite",
          "Moonstone",
          "Obsidian",
          "Onyx",
          "Irregular freshwater Pearl",
          "Peridot",
          "Blue Quartz",
          "Rose Quartz",
          "Smoky Quartz",
          "Star Quartz",
          "Rhodochrosite",
          "Rock Crystal",
          "Sard",
          "Sardonyx",
          "Tiger Eye",
          "Turquoise",
          "Zircon"
        ]
      }
    },
    "semiprecious gem" => {
      (1..20) => {
        value: [ 2, 4, 10 ],
        names: [
          "Alexandrite", 
          "Amber",
          "Amethyst",
          "Aquamarine",
          "Chysoberyl",
          "Coral",
          "Violet Garnet",
          "Red Garnet",
          "Brown-Green Garnet",
          "Jade",
          "Jet",
          "White Pearl", 
          "Black Pearl",
          "Golden Pearl",
          "Pink Pearl",
          "Red Spinel",
          "Red-Brown Spinel",
          "Deep Blue Spinel",
          "Deep Green Spinel",
          "Golden-Yellow Topaz",
          "Tourmaline"
        ]
      }
    },
    "precious gem" => {
      (1..16) => {
        value: [ 4, 4, 10 ],
        names: [
          "Emerald",
          "White Opal",
          "Black Opal",
          "Fire Opal",
          "Blue Sapphire",
          "Fiery Yellow Corundum",
          "Rich Purple Corundum",
          "Blue Star Sapphire",
          "Black Star Sapphire",
          "Star Ruby"
        ]
      },
      (17..20) => {
        value: [ 2, 4, 100 ],
        names: [
          "Clearest bright green Emerald",
          "Blue-white Diamond",
          "Canary Diamond",
          "Brown Diamond",
          "Blue Diamond",
          "Jacinth"
        ]
      }
    },
    "decorative art object" => {
      (1..12) => {
        value: [ 1, 10, 10 ],
        names: [
          "Silver ewer",
          "Carved bone statuette",
          "Carved ivory statuette",
          "Finely-wrought small gold bracelet",
          "Cloth-of-gold vestment",
          "Black velvet mask with numerous citrines",
          "Silver chalice with lapis lazuli gem"
        ]
      },
      (13..20) => {
        value: [ 3, 6, 10 ],
        names: [
          "Large well-done wool tapestry",
          "Brass mug with jade inlay",
          "Silver comb with moonstone",
          "Silver-plated steel longsword with jet jewel in hilt"
        ]
      }
    },
    "fine art object" => {
      (1..9) => {
        value: [ 1, 6, 100 ],
        names: [
          "Carved harp of exotic wood with ivory inlay and zircon gem",
          "Solid gold idol (10lb)",
          "Gold dragon comb with red garnet eye",
          "Gold and topaz bottle stopper cork",
          "Ceremonial electrum dagger with a star ruby in the pommel"
        ]
      },
      (10..16) => {
        value: [ 1, 10, 100 ],
        names: [
          "Eye patch with mock eye of sapphire and moonstone",
          "Fire opal pendant on a fine gold chain",
          "Old masterpiece painting",
          "Embroidered silk and velvet mantel with numerous moonstones",
          "Sapphire pendant on a gold chain",
          "Embroidered and bejeweled glove",
          "Jeweled anklet",
          "Gold music box"
        ]
      },
      (17..20) => {
        value: [ 2, 6, 100 ],
        names: [
          "Golden circlet with four aquamarines",
          "A string of small pink pearls",
          "Jeweled gold crown",
          "Jeweled electrum ring",
          "Gold and ruby ring",
          "Gold cup set with emeralds"
        ]
      }
    }
  }

  def self.generate_treasure(hash, level, modifier)
    treasure = {}
    hash.each do |item_type, ranges|
      puts "Calculating for #{item_type}" if $VERBOSE
      type_roll = roll(1,20) + level + modifier
      ranges.each do |range, found|
        found[3] ||= 1
        found[4] ||= 0
        if range.include? type_roll
          number = ( roll(found[1], found[2]) * found[3] ) - found[4]
          if DND5eTreasure::TREASURE_DETAIL.include? found[0]
            number.times do 
              detail_roll = roll(1,20)
              detail = DND5eTreasure::TREASURE_DETAIL[found[0]].inject(nil) do |memo, (r,d)|
                if r.include? detail_roll
                  memo = d
                end
                d
              end

              name = detail[:names].sample
              special_value = roll(detail[:value][0], detail[:value][1]) * (detail[:value][2] || 1)

              treasure[name] ||= { :special => [], :number => 0, :type => found[0] }
              treasure[name][:number] += 1
              treasure[name][:special] += [ special_value ]
            end
          else
            treasure[found[0]] ||= { :special => [], :number => 0, :type => found[0] }
            treasure[found[0]][:number] += number
          end
          break
        end
      end
    end
    treasure
  end

  def self.generate(type, level)
    treasure = DND5eTreasure.generate_treasure( DND5eTreasure::TREASURE_TABLES[type], level, 0 )
    p treasure if $VERBOSE
    output = []
    treasure.sort_by { |(t,c)| c[:type] }.each do |t,c|
      if treasure.count { |(_t,_c)| _c[:type] == c[:type] } > 1
        if type != c[:type]
          total_value = treasure.select { |_t,_c| _c[:type] == c[:type] }.inject(0) { |memo,(_t,_c)| memo += _c[:special].inject(:+) }
          output << "#{c[:type]}s worth #{total_value}gp: "
        end
        indent = 1
      else
        indent = 0
      end
      type = c[:type]

      if c[:special].count > 1
        output << "#{ "  " * indent}#{c[:number]} #{t}#{c[:number] > 1 ? 's' : ''} (worth #{c[:special].inject(:+)} gold pieces)"
        c[:special].each_with_object(Hash.new(0)) { |v,h| h[v] += 1 }.sort_by { |(k,v)| v }.each do |v,count|
          output << "#{"  " * (indent + 1)}#{count} x #{v} gp"
        end
      elsif c[:special].count == 1
        output << "#{"  " * (indent)}#{c[:number]} #{t}#{c[:number] > 1 ? 's' : ''} (worth #{c[:special].first} gold pieces)"
      else
        output << "#{"  " * indent}#{c[:number]} #{t}#{c[:number] > 1 ? 's' : ''}"
      end
    end
    output
  end
end

module CCCB::Core::Treasure
  extend Module::Requirements

  needs :bot
  

  def module_load

    add_request :treasure, /^\s*treasure(?:\s+(?<type>pouch|chest)(?:\s+(?<level>\d+)))\s*$/i do |match, message|
      type = match[:type] || 'pouch'
      level = match[:level].to_i || 1
      
      DND5eTreasure.generate( type, level )
    end

    add_help(
      :treasure,
      "treasure",
      "Generate some treasure, D&D 5th-edition style",
      [ 
      ]
    )

  end

end

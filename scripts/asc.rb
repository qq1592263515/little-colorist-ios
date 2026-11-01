#!/usr/bin/env ruby
# frozen_string_literal: true
#
# App Store Connect API helper for the store build.
#
# It creates the Mac App Store signing material (Apple Distribution and
# Mac Installer Distribution certificates, the bundle id and the
# Mac App Store provisioning profile) without using the web UI.
#
# Credentials are read from the environment:
#   APPLE_KEY_ID            key id of the App Store Connect API key
#   APPLE_ISSUER_ID         issuer id shown next to the key
#   APPLE_PRIVATE_KEY_PATH  path of the downloaded AuthKey_XXXX.p8
#
# Usage (run from the repository root):
#   ruby Support/AppStore/asc.rb check
#   ruby Support/AppStore/asc.rb list-apps
#   ruby Support/AppStore/asc.rb app-info [APP_ID]
#   ruby Support/AppStore/asc.rb get "/v1/path?query=1"
#   ruby Support/AppStore/asc.rb patch "/v1/path" '{"data":{...}}'
#   ruby Support/AppStore/asc.rb post "/v1/path" '{"data":{...}}'
#   ruby Support/AppStore/asc.rb list-certs
#   ruby Support/AppStore/asc.rb create-cert MAC_APP_DISTRIBUTION CSR OUT.cer
#   ruby Support/AppStore/asc.rb create-cert MAC_INSTALLER_DISTRIBUTION CSR OUT.cer
#   ruby Support/AppStore/asc.rb install-cert OUT.cer
#   ruby Support/AppStore/asc.rb ensure-bundle-id IDENTIFIER NAME
#   ruby Support/AppStore/asc.rb create-profile IDENTIFIER PROFILE_NAME OUT.provisionprofile
#   ruby Support/AppStore/asc.rb upload-screenshots VERSION_LOCALIZATION_ID DIR
#   ruby Support/AppStore/asc.rb upload-review-attachment REVIEW_DETAIL_ID FILE

require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"
KEYCHAIN = File.expand_path("~/Library/Keychains/login.keychain-db")

def fatal(message)
  warn "error: #{message}"
  exit 1
end

def env!(name)
  value = ENV[name].to_s
  fatal("missing environment variable #{name}") if value.empty?
  value
end

def b64url(data)
  Base64.urlsafe_encode64(data, padding: false)
end

# ES256 JWT, the signature has to be the raw 64 byte R||S form.
def auth_token
  @auth_token ||= begin
    key = OpenSSL::PKey.read(File.read(env!("APPLE_PRIVATE_KEY_PATH")))
    header = { "alg" => "ES256", "kid" => env!("APPLE_KEY_ID"), "typ" => "JWT" }
    now = Time.now.to_i
    payload = {
      "iss" => env!("APPLE_ISSUER_ID"),
      "iat" => now,
      "exp" => now + 900,
      "aud" => "appstoreconnect-v1"
    }
    signing_input = "#{b64url(JSON.dump(header))}.#{b64url(JSON.dump(payload))}"
    der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
    pairs = OpenSSL::ASN1.decode(der).value.map { |int| int.value.to_s(16).rjust(64, "0")[-64, 64] }
    "#{signing_input}.#{b64url([pairs.join].pack("H*"))}"
  end
end

def call_api(method, path, body = nil)
  uri = URI.parse(path.start_with?("http") ? path : "#{API_BASE}#{path}")
  request = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch, delete: Net::HTTP::Delete }
            .fetch(method).new(uri)
  request["Authorization"] = "Bearer #{auth_token}"
  request["Content-Type"] = "application/json"
  request["Accept"] = "application/json"
  request.body = JSON.dump(body) if body
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 20, read_timeout: 90) do |http|
    http.request(request)
  end
  body_text = response.body.to_s
  payload = if body_text.empty?
              {}
            else
              begin
                JSON.parse(body_text)
              rescue JSON::ParserError
                { "raw" => body_text }
              end
            end
  [response.code.to_i, payload]
end

def api!(method, path, body = nil)
  code, payload = call_api(method, path, body)
  unless (200..299).cover?(code)
    fatal("#{method.to_s.upcase} #{path} -> HTTP #{code}\n#{JSON.pretty_generate(payload)}")
  end
  payload
end

def all_certificates
  list = []
  next_url = "/v1/certificates?limit=200"
  while next_url
    data = api!(:get, next_url)
    list.concat(data["data"] || [])
    next_url = data.dig("links", "next")&.sub(API_BASE, "")
  end
  list
end

def certificates_of_type(type)
  all_certificates.select { |cert| cert.dig("attributes", "certificateType") == type }
end

def print_certificates(certs)
  return puts("  (none)") if certs.empty?
  certs.each do |cert|
    attrs = cert["attributes"]
    puts "  #{attrs['name']} | #{attrs['certificateType']} | expires #{attrs['expirationDate']} | id #{cert['id']}"
  end
end

def decode_to_file(content, path)
  File.binwrite(path, Base64.decode64(content))
  puts "wrote #{path} (#{File.size(path)} bytes)"
end

# 按 App Store Connect 返回的分片清单把文件推上去。
def push_bytes(path, operations)
  operations.each do |operation|
    uri = URI.parse(operation["url"])
    request = Net::HTTP::Put.new(uri)
    (operation["requestHeaders"] || []).each { |header| request[header["name"]] = header["value"] }
    request.body = File.binread(path, operation["length"], operation["offset"])
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 30, read_timeout: 120) do |http|
      response = http.request(request)
      fatal("upload failed with HTTP #{response.code}") unless (200..299).cover?(response.code.to_i)
    end
  end
end

# 价格点和可用地区的 id 里塞了 base64 编码的 JSON，地区在 "t" 字段。
def price_point_territory(point_id)
  padded = point_id + "=" * ((4 - (point_id.size % 4)) % 4)
  JSON.parse(Base64.urlsafe_decode64(padded))["t"]
rescue StandardError
  nil
end

def find_bundle_id(identifier)
  list = []
  next_url = "/v1/bundleIds?limit=200"
  while next_url
    data = api!(:get, next_url)
    list.concat(data["data"] || [])
    next_url = data.dig("links", "next")&.sub(API_BASE, "")
  end
  list.find { |item| item.dig("attributes", "identifier") == identifier }
end

command = ARGV.shift

case command
when "check"
  api!(:get, "/v1/bundleIds?limit=1")
  puts "ok: the App Store Connect API key works."

when "list-apps"
  apps = api!(:get, "/v1/apps?limit=50")["data"] || []
  if apps.empty?
    puts "no app records yet"
  else
    apps.each do |app|
      attrs = app["attributes"]
      puts "  #{attrs['name']} | #{attrs['bundleId']} | #{attrs['sku']} | #{attrs['primaryLocale']} | id #{app['id']}"
    end
  end

when "app-info"
  app = if ARGV[0]
          api!(:get, "/v1/apps/#{ARGV[0]}")["data"]
        else
          (api!(:get, "/v1/apps?limit=1")["data"] || []).first
        end
  fatal("no app record found") unless app
  attrs = app["attributes"]
  puts "app: #{attrs['name']} | #{attrs['bundleId']} | sku #{attrs['sku']} | id #{app['id']}"
  infos = api!(:get, "/v1/apps/#{app['id']}/appInfos?include=primaryCategory,secondaryCategory,ageRatingDeclaration")
  (infos["data"] || []).each do |info|
    puts "appInfo #{info['id']} state=#{info.dig('attributes', 'state')}"
  end
  (infos["included"] || []).each do |included|
    case included["type"]
    when "appCategories"
      puts "  category #{included['id']}"
    when "ageRatingDeclarations"
      puts "  age rating declaration #{included['id']}:"
      (included["attributes"] || {}).sort.each do |key, value|
        puts "    #{key} = #{value.inspect}" unless value.nil?
      end
    end
  end

when "get"
  path = ARGV[0] || fatal("usage: get /v1/path")
  puts JSON.pretty_generate(api!(:get, path))

when "patch"
  path, body = ARGV
  fatal("usage: patch /v1/path '{json}'") unless path && body
  puts JSON.pretty_generate(api!(:patch, path, JSON.parse(body)))

when "post"
  path, body = ARGV
  fatal("usage: post /v1/path '{json}'") unless path && body
  puts JSON.pretty_generate(api!(:post, path, JSON.parse(body)))

when "delete"
  path = ARGV[0]
  fatal("usage: delete /v1/path") unless path
  puts JSON.pretty_generate(api!(:delete, path))

when "upload-screenshots"
  localization_id, directory, display_type = ARGV
  display_type = "APP_DESKTOP" if display_type.to_s.empty?
  fatal("usage: upload-screenshots VERSION_LOCALIZATION_ID DIR [DISPLAY_TYPE]") unless localization_id && directory
  files = Dir.glob(File.join(directory, "*.png")).sort
  fatal("no png files in #{directory}") if files.empty?

  sets = api!(:get, "/v1/appStoreVersionLocalizations/#{localization_id}/appScreenshotSets")["data"] || []
  set = sets.find { |item| item.dig("attributes", "screenshotDisplayType") == display_type }
  if set
    existing = api!(:get, "/v1/appScreenshotSets/#{set['id']}/appScreenshots")["data"] || []
    existing.each { |shot| api!(:delete, "/v1/appScreenshots/#{shot['id']}") }
    puts "reusing screenshot set #{set['id']} (replaced #{existing.size} existing)"
  else
    set = api!(:post, "/v1/appScreenshotSets", {
      "data" => {
        "type" => "appScreenshotSets",
        "attributes" => { "screenshotDisplayType" => display_type },
        "relationships" => {
          "appStoreVersionLocalization" => {
            "data" => { "type" => "appStoreVersionLocalizations", "id" => localization_id }
          }
        }
      }
    })["data"]
    puts "created screenshot set #{set['id']}"
  end

  files.each do |path|
    checksum = Digest::MD5.file(path).hexdigest
    shot = api!(:post, "/v1/appScreenshots", {
      "data" => {
        "type" => "appScreenshots",
        "attributes" => { "fileSize" => File.size(path), "fileName" => File.basename(path) },
        "relationships" => {
          "appScreenshotSet" => { "data" => { "type" => "appScreenshotSets", "id" => set["id"] } }
        }
      }
    })["data"]

    push_bytes(path, shot.dig("attributes", "uploadOperations") || [])
    api!(:patch, "/v1/appScreenshots/#{shot['id']}", {
      "data" => {
        "type" => "appScreenshots",
        "id" => shot["id"],
        "attributes" => { "uploaded" => true, "sourceFileChecksum" => checksum }
      }
    })
    puts "uploaded #{File.basename(path)} (#{File.size(path)} bytes)"
  end

when "upload-iap-screenshots"
  kind, resource_id, path = ARGV
  unless %w[iap subscription].include?(kind.to_s) && resource_id && path
    fatal("usage: upload-iap-screenshots iap|subscription RESOURCE_ID PNG")
  end
  # relationship 的键和它指向的资源类型名不一样，这里分开写。
  collection, relationship, related_type = if kind == "iap"
                                             ["/v1/inAppPurchaseAppStoreReviewScreenshots", "inAppPurchaseV2", "inAppPurchases"]
                                           else
                                             ["/v1/subscriptionAppStoreReviewScreenshots", "subscription", "subscriptions"]
                                           end
  resource_type = collection.sub("/v1/", "")

  shot = api!(:post, collection, {
    "data" => {
      "type" => resource_type,
      "attributes" => { "fileSize" => File.size(path), "fileName" => File.basename(path) },
      "relationships" => {
        relationship => { "data" => { "type" => related_type, "id" => resource_id } }
      }
    }
  })["data"]

  push_bytes(path, shot.dig("attributes", "uploadOperations") || [])
  api!(:patch, "#{collection}/#{shot['id']}", {
    "data" => {
      "type" => resource_type,
      "id" => shot["id"],
      "attributes" => {
        "uploaded" => true,
        "sourceFileChecksum" => Digest::MD5.file(path).hexdigest
      }
    }
  })
  puts "uploaded #{File.basename(path)} for #{kind} #{resource_id} (screenshot #{shot['id']})"

when "upload-review-attachment"
  review_detail_id, path = ARGV
  fatal("usage: upload-review-attachment REVIEW_DETAIL_ID FILE") unless review_detail_id && path
  fatal("file not found: #{path}") unless File.file?(path)

  attachment = api!(:post, "/v1/appStoreReviewAttachments", {
    "data" => {
      "type" => "appStoreReviewAttachments",
      "attributes" => {
        "fileName" => File.basename(path),
        "fileSize" => File.size(path)
      },
      "relationships" => {
        "appStoreReviewDetail" => {
          "data" => { "type" => "appStoreReviewDetails", "id" => review_detail_id }
        }
      }
    }
  })["data"]

  push_bytes(path, attachment.dig("attributes", "uploadOperations") || [])
  uploaded = api!(:patch, "/v1/appStoreReviewAttachments/#{attachment['id']}", {
    "data" => {
      "type" => "appStoreReviewAttachments",
      "id" => attachment["id"],
      "attributes" => {
        "uploaded" => true,
        "sourceFileChecksum" => Digest::MD5.file(path).hexdigest
      }
    }
  })["data"]

  puts "uploaded #{File.basename(path)} to review detail #{review_detail_id}"
  puts "attachment id: #{uploaded['id']}"
  puts "delivery state: #{uploaded.dig('attributes', 'assetDeliveryState', 'state') || 'unknown'}"

when "backfill-subscription-prices"
  subscription_id = ARGV[0]
  fatal("usage: backfill-subscription-prices SUBSCRIPTION_ID") unless subscription_id

  # 先收集已经定过价的地区，避免重复创建。
  priced = {}
  next_url = "/v1/subscriptions/#{subscription_id}/prices?include=territory&limit=200"
  while next_url
    data = api!(:get, next_url)
    (data["data"] || []).each do |price|
      territory = price.dig("relationships", "territory", "data", "id")
      priced[territory] = true if territory
    end
    next_url = data.dig("links", "next")&.sub(API_BASE, "")
  end
  fatal("这个订阅还没有基准价格，先在 App Store Connect 里设一个基准地区价格") if priced.empty?

  base_territory = priced.key?("CHN") ? "CHN" : priced.keys.first
  base_point = nil
  next_url = "/v1/subscriptions/#{subscription_id}/prices?include=subscriptionPricePoint,territory&limit=200"
  while next_url && base_point.nil?
    data = api!(:get, next_url)
    (data["data"] || []).each do |price|
      next unless price.dig("relationships", "territory", "data", "id") == base_territory

      base_point = price.dig("relationships", "subscriptionPricePoint", "data", "id")
    end
    next_url = data.dig("links", "next")&.sub(API_BASE, "")
  end
  fatal("找不到 #{base_territory} 的价格点") unless base_point

  # 苹果的等值价格点接口会给出每个地区的等价价位，直接拿来补。
  targets = []
  next_url = "/v1/subscriptionPricePoints/#{base_point}/equalizations?limit=200"
  while next_url
    data = api!(:get, next_url)
    (data["data"] || []).each do |point|
      territory = price_point_territory(point["id"])
      next if territory.nil? || priced[territory]

      targets << [territory, point["id"], point.dig("attributes", "customerPrice")]
    end
    next_url = data.dig("links", "next")&.sub(API_BASE, "")
  end

  puts "基准地区 #{base_territory}，已有 #{priced.size} 个地区，待补 #{targets.size} 个"
  failures = []
  targets.each do |territory, point_id, customer_price|
    api!(:post, "/v1/subscriptionPrices", {
      "data" => {
        "type" => "subscriptionPrices",
        "attributes" => { "startDate" => nil },
        "relationships" => {
          "subscription" => { "data" => { "type" => "subscriptions", "id" => subscription_id } },
          "subscriptionPricePoint" => { "data" => { "type" => "subscriptionPricePoints", "id" => point_id } },
          "territory" => { "data" => { "type" => "territories", "id" => territory } }
        }
      }
    })
    puts "  #{territory} -> #{customer_price}"
  rescue StandardError => error
    failures << "#{territory}: #{error.message.to_s[0, 140]}"
  end

  if failures.empty?
    puts "补齐完成：#{targets.size} 个地区"
  else
    puts "有 #{failures.size} 个地区失败："
    failures.first(10).each { |line| puts "  #{line}" }
  end

when "list-certs"
  puts "certificates:"
  print_certificates(all_certificates)

when "create-cert"
  type, csr_path, out_path = ARGV
  fatal("usage: create-cert TYPE CSR OUT.cer") unless type && csr_path && out_path
  existing = certificates_of_type(type)
  unless existing.empty?
    puts "existing certificates of type #{type}:"
    print_certificates(existing)
  end
  csr = File.read(csr_path)
  fatal("#{csr_path} does not look like a CSR") unless csr.include?("CERTIFICATE REQUEST")
  body = {
    "data" => {
      "type" => "certificates",
      "attributes" => { "certificateType" => type, "csrContent" => csr }
    }
  }
  data = api!(:post, "/v1/certificates", body)
  cert = data["data"]
  puts "created #{type} id #{cert['id']} name #{cert.dig('attributes', 'name')}"
  decode_to_file(cert.dig("attributes", "certificateContent"), out_path)

when "install-cert"
  path = ARGV[0]
  fatal("usage: install-cert FILE.cer") unless path
  system("security", "add-certificates", "-k", KEYCHAIN, path) || fatal("security add-certificates failed")
  puts `security find-identity -v -p codesigning`

when "ensure-bundle-id"
  identifier, name = ARGV
  fatal("usage: ensure-bundle-id IDENTIFIER NAME") unless identifier && name
  found = find_bundle_id(identifier)
  if found
    puts "bundle id exists: #{identifier} (id #{found['id']})"
  else
    body = {
      "data" => {
        "type" => "bundleIds",
        "attributes" => { "identifier" => identifier, "name" => name, "platform" => "MAC_OS" }
      }
    }
    found = api!(:post, "/v1/bundleIds", body)["data"]
    puts "created bundle id: #{identifier} (id #{found['id']})"
  end
  capabilities = api!(:get, "/v1/bundleIds/#{found['id']}/bundleIdCapabilities")["data"] || []
  have = capabilities.map { |cap| cap.dig("attributes", "capabilityType") }
  puts "capabilities: #{have.empty? ? '(none)' : have.join(', ')}"
  unless have.include?("IN_APP_PURCHASE")
    api!(:post, "/v1/bundleIdCapabilities", {
      "data" => {
        "type" => "bundleIdCapabilities",
        "attributes" => { "capabilityType" => "IN_APP_PURCHASE" },
        "relationships" => { "bundleId" => { "data" => { "type" => "bundleIds", "id" => found["id"] } } }
      }
    })
    puts "enabled capability IN_APP_PURCHASE"
  end

when "create-profile"
  identifier, profile_name, out_path = ARGV
  fatal("usage: create-profile IDENTIFIER PROFILE_NAME OUT.provisionprofile") unless identifier && profile_name && out_path
  bundle = find_bundle_id(identifier) || fatal("bundle id #{identifier} not found")
  certs = certificates_of_type("MAC_APP_DISTRIBUTION")
  fatal("no MAC_APP_DISTRIBUTION certificate in the team") if certs.empty?
  cert = certs.max_by { |item| item.dig("attributes", "expirationDate").to_s }
  puts "using certificate #{cert['id']} (expires #{cert.dig('attributes', 'expirationDate')})"
  body = {
    "data" => {
      "type" => "profiles",
      "attributes" => { "name" => profile_name, "profileType" => "MAC_APP_STORE" },
      "relationships" => {
        "bundleId" => { "data" => { "type" => "bundleIds", "id" => bundle["id"] } },
        "certificates" => { "data" => [{ "type" => "certificates", "id" => cert["id"] }] }
      }
    }
  }
  data = api!(:post, "/v1/profiles", body)
  profile = data["data"]
  puts "created profile #{profile.dig('attributes', 'name')} id #{profile['id']}"
  decode_to_file(profile.dig("attributes", "profileContent"), out_path)

when "create-ios-profile"
  identifier, profile_name, out_path = ARGV
  fatal("usage: create-ios-profile IDENTIFIER PROFILE_NAME OUT.mobileprovision") unless identifier && profile_name && out_path
  bundle = find_bundle_id(identifier) || fatal("bundle id #{identifier} not found")
  certs = certificates_of_type("IOS_DISTRIBUTION")
  fatal("no IOS_DISTRIBUTION certificate in the team") if certs.empty?
  cert = certs.max_by { |item| item.dig("attributes", "expirationDate").to_s }
  puts "using certificate #{cert['id']} (expires #{cert.dig('attributes', 'expirationDate')})"
  body = {
    "data" => {
      "type" => "profiles",
      "attributes" => { "name" => profile_name, "profileType" => "IOS_APP_STORE" },
      "relationships" => {
        "bundleId" => { "data" => { "type" => "bundleIds", "id" => bundle["id"] } },
        "certificates" => { "data" => [{ "type" => "certificates", "id" => cert["id"] }] }
      }
    }
  }
  data = api!(:post, "/v1/profiles", body)
  profile = data["data"]
  puts "created profile #{profile.dig('attributes', 'name')} id #{profile['id']}"
  decode_to_file(profile.dig("attributes", "profileContent"), out_path)

else
  fatal("unknown command #{command.inspect}, see the header of this file for usage")
end

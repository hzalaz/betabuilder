require 'rest_client'
require 'json'
require 'tmpdir'
require 'fileutils'
require 'zip/zip'

module BetaBuilder
  module DeploymentStrategies
    class TestFlight < Strategy
      include Rake::DSL
      include FileUtils
      ENDPOINT = "https://testflightapp.com/api/builds.json"
      
      def extended_configuration_for_strategy
        proc do
          def generate_release_notes(&block)
            self.release_notes = block if block
          end
        end
      end
      
      def deploy
        release_notes = get_notes

        File.delete(@configuration.built_app_dsym_zip_path) if File.exists?(@configuration.built_app_dsym_zip_path)
        Zip::ZipFile.open("#{@configuration.built_app_dsym_zip_path}", Zip::ZipFile::CREATE) do |zipfile|
          Dir["#{@configuration.built_app_dsym_path}/**/*"].each { |f|
            name = f.sub("#{@configuration.built_app_dsym_path}/", '')
            path = "#{@configuration.built_app_dsym_path}/#{f}"
            zipfile.add(name, f) if File.file?f
          }
        end

        payload = {
          :api_token          => @configuration.api_token,
          :team_token         => @configuration.team_token,
          :file               => File.new(@configuration.ipa_path, 'rb'),
          :notes              => release_notes,
          :distribution_lists => (@configuration.distribution_lists || []).join(","),
          :notify             => @configuration.notify || false,
          :replace            => @configuration.replace || false,
          :dsym               => File.new(@configuration.built_app_dsym_zip_path, 'rb')
        }
        puts "Uploading build to TestFlight..."
        if @configuration.verbose
          puts "ipa path: #{@configuration.ipa_path}"
          puts "release notes: #{release_notes}"
        end
        
        if @configuration.dry_run 
          puts '** Dry Run - No action here! **'
          return
        end
        
        begin
          response = RestClient.post(ENDPOINT, payload, :accept => :json)
        rescue => e
          response = e.response
        end
        
        if (response.code == 201) || (response.code == 200)
          puts "Upload complete."
        else
          puts "Upload failed. (#{response})"
        end
      end
      
      private
      
      def get_notes
        notes = @configuration.release_notes_text
        notes || get_notes_using_editor || get_notes_using_prompt
      end
      
      def get_notes_using_editor
        return unless (editor = ENV["EDITOR"])

        dir = Dir.mktmpdir
        begin
          filepath = "#{dir}/release_notes"
          system("#{editor} #{filepath}")
          @configuration.release_notes = File.read(filepath)
        ensure
          rm_rf(dir)
        end
      end
      
      def get_notes_using_prompt
        puts "Enter the release notes for this build (hit enter twice when done):\n"
        @configuration.release_notes = gets_until_match(/\n{2}$/).strip
      end
      
      def gets_until_match(pattern, string = "")
        if (string += STDIN.gets) =~ pattern
          string
        else
          gets_until_match(pattern, string)
        end
      end
    end
  end
end

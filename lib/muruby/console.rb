require 'rubygems'
require 'thor'
require 'gettext'
require 'rbconfig'
require 'fileutils'
require 'delegate'

$GIT_REPO_MRUBY="git://github.com/mruby/mruby.git"
$HG_REPO_SDL2= {
#  'SDL' => "http://hg.libsdl.org/SDL",
  'SDL' => 'http://www.libsdl.org/release/SDL2-2.0.1.tar.gz',
#  'SDL_image' => "http://hg.libsdl.org/SDL_image/",
  'SDL_image' => 'http://www.libsdl.org/projects/SDL_image/release/SDL2_image-2.0.0.tar.gz',
#  'SDL_mixer' => "http://hg.libsdl.org/SDL_mixer/",
  'SDL_mixer' => 'http://www.libsdl.org/projects/SDL_mixer/release/SDL2_mixer-2.0.0.tar.gz',
#  'SDL_ttf' => "http://hg.libsdl.org/SDL_ttf/"
  'SDL_ttf' => 'http://www.libsdl.org/projects/SDL_ttf/release/SDL2_ttf-2.0.12.tar.gz'
}

module CacheDir
  
  def cache_directory(basename)
    local_file = File.join(cache_path, basename)
    Dir.mkdir(cache_path) unless File.exists?(cache_path)
    yield(local_file)
  end
  
end

class Curl < SimpleDelegator
  include CacheDir
  
  def clone(dir, url, options = "")
    cache_directory(File.basename(url)) { |local_file|
      run("curl -C - %s -o %s %s" % [url, local_file, options])
      run("tar -xzf %s" % [local_file])
      run("mv %s %s" % [File.basename(url, ".tar.gz"), dir])
    }
  end
  
  def pull(dir)
  end
  
end

class Git < SimpleDelegator
  include CacheDir
  
  def clone(dir, url, options = "")
    cache_directory(File.basename(dir)) {|local_path|
      run("git clone %s %s %s" % [url, options, local_path])
      run("git clone %s %s %s" % [local_path, options, dir])
    }
  end
  
  def pull(dir)
    Dir.chdir(dir) do
      run("git pull")
    end
  end
end

class Hg < SimpleDelegator
  include CacheDir
  
  def clone(dir, url, options = {})
    cache_directory(File.basename(dir)) {|local_path|
      run("hg clone %s %s %s" % [url, options, local_path])
      run("hg clone %s %s %s" % [url, options, dir])
    }
  end
  
  def pull(dir)
    run("hg pull %s" % [dir])
  end
end

module Build
  #directory for build code for the host
  def build_host_path
    File.join(app_path(), 'core', 'build_host')
  end

  def build_android_path
    File.join(app_path(), 'core', 'build_android')
  end
  
  def core_path
    File.join(app_path(), 'core')
  end
  

  def _configure_mruby(app, mruby_path, options = {})
    options[:dev_github_mruby_sdl2] ||= 'pichurriaj/mruby-sdl2'
    
    gems_common = [
                   'mrbgems/mruby-math',
                   'mrbgems/mruby-enum-ext',
                   'mrbgems/mruby-random',
                   'mrbgems/mruby-proc-ext',
                   'mrbgems/mruby-exit',
                   'mrbgems/mruby-fiber',
                   'mrbgems/mruby-struct',
                   'mrbgems/mruby-sprintf',
                   'mrbgems/mruby-string-ext',
                   'mrbgems/mruby-object-ext',
                   'mrbgems/mruby-array-ext',
                   'mrbgems/mruby-hash-ext',
                   'mrbgems/mruby-symbol-ext',
                   'mrbgems/mruby-eval'
                  ]
    gems_base = [
                 {
                   :github => options[:dev_github_mruby_sdl2],
                   :branch => 'master',
                   :cc => {
                     'cc.include_paths' => [File.join(build_host_path, 'include')],
                     'linker.libraries' => ['SDL2'],
                     'linker.library_paths' => [File.join(build_host_path, 'lib')]
                   }
                 },
                 'mrbgems/mruby-print',
                 'mrbgems/mruby-bin-mirb',
                 'mrbgems/mruby-bin-mruby'
    ] | gems_common | [
      { :github => 'iij/mruby-dir', :branch => 'master' },
      { :github => 'iij/mruby-io', :branch => 'master' },
      { :github => 'iij/mruby-tempfile', :branch => 'master' },
      { :github => 'iij/mruby-require', :branch => 'master' }
    ]


    gems_android = [
                    {
                      :github => options[:dev_github_mruby_sdl2],
                      :branch => 'master',
                      :cc => {
                        'cc.include_paths' => [File.join(build_host_path, 'include'),
                                               File.join(ENV['ANDROID_NDK_HOME'], 'sources/android/support/include/'),
                                              ],
                        #'linker.libraries' => [%w(SDL2)],
                        #'linker.library_paths' => [File.join(build_android_path, 'libs', 'armeabi')]
                      },
                      
                    },
                    {
                      :github => 'pichurriaj/mruby-print-android',
                      :branch => 'master'
                    }
                ] | gems_common

    _configure_mruby_host(mruby_path, gems_base)
    _configure_mruby_android(mruby_path, gems_android) if options[:build_android]
    
    inside(mruby_path) do
      run("rake clean && rake")
    end
  end

  #changes name logo and personalize the engine
  def _personalize_android(app, package)
    android_manifest_path = File.join(build_android_path, 'AndroidManifest.xml')
    gsub_file android_manifest_path, 'package="com.pichurriajuegos.muruby"', "package=\"%s\"" % package
    android_values_path = File.join(build_android_path, 'res', 'values', 'strings.xml')
    gsub_file android_values_path '<string name="app_name">muruby</string>', '<string name="app_name">%s</string>' % app
  end
  
 
  def _configure_mruby_host(mruby_path, gems_base)
    _mruby_update_build_conf(mruby_path, gems_base, "MRuby::Build.new do |conf|\n", "#AUTOMATIC MRBGEMS --NO EDIT--\n")
    _mruby_update_build_conf(mruby_path, gems_base, "MRuby::Build.new('host-debug') do |conf|\n", "#AUTOMATIC MRBGEMS DEBUG --NO EDIT--\n")
  end
  
  def _configure_mruby_android(mruby_path, gems_base)
    key_to_append = "#AUTOMATIC GEMS ANDROID --NO EDIT--\n"
    insert_into_file File.join(mruby_path, 'build_config.rb'), :after => "# Define cross build settings\n" do
      out = "#AUTOMATIC CROSSBUILD ANDROID\n"
      out += "MRuby::CrossBuild.new('androideabi') do |conf|\n"
      out += "toolchain :androideabi\n"
      out += "conf.cc.defines = %w(DISABLE_STDIO)\n"
      out += "conf.bins = []\n"
      out += key_to_append
      out += "end\n"
      out
    end
    _mruby_update_build_conf(mruby_path, gems_base, key_to_append, "#AUTOMATIC ANDROID MBRGEMS\n")


    #copy skel android projct
    #@todo how do recursive??
    run("rm -rf %s" % build_android_path)
    run("cp -ra %s %s" % [_skel_root('android-project'), build_android_path])
    
    sdl_android_path = File.join(build_android_path, 'jni', 'SDL')
    repo('curl').clone(sdl_android_path, $HG_REPO_SDL2['SDL'])  unless File.directory?(sdl_android_path)
    
    if options[:enable_sdl_image]
      sdl_image_android_path = File.join(build_android_path, 'jni', 'SDL_image')
      repo('curl').clone(sdl_image_android_path, $HG_REPO_SDL2['SDL_image']) unless File.directory?(sdl_image_android_path)
      sdl_image_android_path_mk = File.join(sdl_image_android_path, 'Android.mk')
      gsub_file sdl_image_android_path_mk, "SUPPORT_WEBP := true", "SUPPORT_WEBP := false"
    end
    
    if options[:enable_sdl_ttf]
      sdl_ttf_android_path = File.join(build_android_path, 'jni', 'SDL_ttf')
      repo('curl').clone(sdl_ttf_android_path, $HG_REPO_SDL2['SDL_ttf']) unless File.directory?(sdl_ttf_android_path)
      sdl_ttf_android_path_mk = File.join(sdl_ttf_android_path, 'Android.mk')
      gsub_file sdl_ttf_android_path_mk, "SUPPORT_JPG := true", "SUPPORT_JPG := false"
    end
    
    if options[:enable_sdl_mixer]
      sdl_mixer_android_path = File.join(build_android_path, 'jni', 'SDL_mixer')
      repo('curl').clone(sdl_mixer_android_path, $HG_REPO_SDL2['SDL_mixer']) unless File.directory?(sdl_mixer_android_path)
    
      sdl_mixer_android_path_mk = File.join(sdl_mixer_android_path, 'Android.mk')
      gsub_file sdl_mixer_android_path_mk, "SUPPORT_MOD_MODPLUG := true", "SUPPORT_MOD_MODPLUG := false"
      gsub_file sdl_mixer_android_path_mk, "SUPPORT_MOD_MIKMOD := true", "SUPPORT_MOD_MIKMOD := false"
      gsub_file sdl_mixer_android_path_mk, "SUPPORT_MP3_SMPEG := true", "SUPPORT_MP3_SMPEG := false"
    end
    

  end

  
  def _mruby_update_build_conf(mruby_path, gems_base, after, tag = "")

    insert_into_file File.join(mruby_path,"build_config.rb"), :after => after do
      gems_base.map do |gem|
        case gem
        when Hash
          out = tag
          out += "\nconf.gem :github => '%s', :branch => '%s' " % [gem[:github], gem[:branch]]
          if gem[:cc]
            out += "do |g|\n"
            out += gem[:cc].map{|k,v|
              case v
              when Array
                v.map{|vc| "\tg.#{k} << '#{vc}'"}.join("\n")
              else
                "\tg.#{k} = '#{v}'"
              end
            }.join("\n")
            out += "\nend\n"
          end
          out
        when String
          "conf.gem '%s'" % gem
        end
      end.join("\n") + "\n"
    end
  end
  

  def _configure_sdl2(app, sdl_path)
    #compile for host
    say("compiling %s for host" % sdl_path)
    @sdl_path = sdl_path
    sdl_lib_path = File.join(build_host_path, 'lib', 'libSDL2.so')
    if File.exists?(sdl_lib_path)
      say("Skipping SDL2...")
      return
    end
    inside(sdl_path) do
      #simulate system install
      run("mkdir include/SDL2")
      run("cp -ra include/* include/SDL2/")
      run("./configure --prefix=%s" % build_host_path, :capture => false)
      run("make")
      run("make install")
      run("make clean")
    end
    if !File.exists?(sdl_lib_path)
      raise RuntimeError, "Failed Compiling SDL2, build manually %s" % sdl_path
    end
  end

  def _configure_sdl2_image(app, sdl_path, sdl_image_path)
    #compile for host
    say("compiling %s for host" % sdl_image_path)
    sdl_image_lib_path = File.join(build_host_path, 'lib', 'libSDL2_image.so')
    if File.exists?(sdl_image_lib_path)
      say("Skipping SDL2 image..")
      return
    end
    inside(sdl_image_path) do
      run("./autogen.sh")
      run("./configure --prefix=%s --with-sdl-prefix=%s" % [build_host_path, build_host_path], :capture => false)
      run("make")
      run("make install")
      run("make clean")
    end
    if !File.exists?(sdl_image_lib_path)
      raise RuntimeError, "Failed Compiling SDL2 image, build manually %s" % sdl_image_path
    end
  end
  
  def _configure_sdl2_ttf(app, sdl_path, sdl_ttf_path)
    #compile for host
    say("compiling %s for host" % sdl_ttf_path)
    sdl_ttf_lib_path = File.join(build_host_path, 'lib', 'libSDL2_ttf.so')
    if File.exists?(sdl_ttf_lib_path)
      say("Skipping SDL2 ttf...")
      return
    end
    inside(sdl_ttf_path) do
      run("./autogen.sh")
      run("./configure --prefix=%s --with-sdl-prefix=%s" % [build_host_path, build_host_path], :capture => false)
      run("make")
      run("make install")
      run("make clean")
    end
    if !File.exists?(sdl_ttf_lib_path)
      raise RuntimeError, "Failed Compiling SDL2 ttf build manually %s" % sdl_ttf_path
    end
    
  end

  def _configure_sdl2_mixer(app, sdl_path, sdl_mixer_path)
    #compile for host
    say("compiling %s for host" % sdl_mixer_path)
    sdl_mixer_lib_path = File.join(build_host_path, 'lib', 'libSDL2_mixer.so')
    if File.exists?(sdl_mixer_lib_path)
      say("Skipping SDL2 mixer...")
      return
    end
    
    inside(sdl_mixer_path) do
      run("./autogen.sh")
      run("./configure --prefix=%s --with-sdl-prefix=%s" % [build_host_path, build_host_path], :capture => false)
      run("make")
      run("make install")
    end
    if !File.exists?(sdl_mixer_lib_path)
      raise RuntimeError, "Failed Compiling SDL2 mixer, build manually %s" % sdl_mixer_path
    end

  end

end

module Muruby
  class Game < Thor
    include Thor::Actions
    include Build

    @@app_path = nil
    def self.source_root
      File.dirname(__FILE__)
    end

    class_option :enable_sdl_mixer, :type => :boolean, :default => false, :desc => "Not Implemented yet"
    class_option :enable_sdl_ttf, :type => :boolean, :default => false, :desc => "Not implemented yet"
    class_option :enable_sdl_image, :type => :boolean, :default => false, :desc => "Not implemented yet"
    class_option :mruby_unstable, :type => :boolean, :default => false, :desc => "Use the master of mruby"
    class_option :dev_github_mruby_sdl2, :type => :string, :default => 'pichurriaj/mruby-sdl2', :desc => "Choose implementation mruby SDL2 on github, ex: pichurriaj/mruby-sdl2."
    class_option :build_android, :type => :boolean, :default => true, :desc => "Build android"
    method_option :package, :type => :string, :default => 'com.pichurriajuegos.muruby', :required => true, :banner => 'ej: com.pichurriajuegos.muruby the package'
    desc 'create <app>', "Create a directory <name> structure with everything need for creating games for Android, and GNU/Linux.
"
    def create(name)
      if options[:build_android]
        abort "Need enviroment variable ANDROID_NDK_HOME" unless ENV["ANDROID_NDK_HOME"]
      end
      
      @@app_path =  File.absolute_path File.join(".", name)
      source_paths << _skel_root()
      _create_app(name)
      _create_core(name)
    end

    no_commands {
      def app_path
        @@app_path
      end
      
      def cache_path
        File.join(Dir.home, ".muruby")
      end

      def repo(type)
        case type
        when 'hg'
          Hg.new(self)
        when 'git'
          Git.new(self)
        when 'curl'
          Curl.new(self)
        else
          raise RuntimeError, "Invalid Cloner %s\n" % [type]
        end
      end

    }
    
    private
    
    def _create_app(name)
      empty_directory "#{name}/app"
      empty_directory "#{name}/app/game"
      copy_file "doc/README_game.md", "#{name}/app/game/README.md"
      copy_file "game/runtime.rb", "#{name}/app/game/runtime.rb"
      copy_file "Rakefile", "#{name}/app/Rakefile"
      copy_file "Gemfile", "#{name}/app/Gemfile"
      copy_file ".gitignore.tmpl", "#{name}/app/.gitignore"
      
      empty_directory "#{name}/app/resources"
      copy_file "doc/README_resources.md", "#{name}/app/resources/README.md"

      empty_directory "#{name}/app/deploy"
      copy_file "doc/README_deploy.md", "#{name}/app/deploy/README.md"
    end
    
    def _create_core(name)
      empty_directory "#{name}/core"

      #download sources
      sdl_path = "#{name}/core/SDL2"
      repo('curl').clone(sdl_path, $HG_REPO_SDL2['SDL']) unless File.directory?(sdl_path)
      sdl_image_path = "#{name}/core/SDL2_image"
      repo('curl').clone(sdl_image_path, $HG_REPO_SDL2['SDL_image']) unless File.directory?(sdl_image_path) if options[:enable_sdl_image]
      sdl_ttf_path = "#{name}/core/SDL2_ttf"
      repo('curl').clone(sdl_ttf_path, $HG_REPO_SDL2['SDL_ttf']) unless File.directory?(sdl_ttf_path) if options[:enable_sdl_ttf]
      sdl_mixer_path = "#{name}/core/SDL2_mixer"
      repo('curl').clone(sdl_mixer_path, $HG_REPO_SDL2['SDL_mixer']) unless File.directory?(sdl_mixer_path) if options[:enable_sdl_mixer]

      
      mruby_path = "#{name}/core/mruby"
      unless File.directory?(mruby_path)
        repo('git').clone(mruby_path, $GIT_REPO_MRUBY)
      end


      inside(mruby_path) do
        unless options[:mruby_unstable] 
          run("git checkout 1.1.0")
        else
          run("git checkout master")
        end
      end
      #mruby-android
      #mruby-require

      #configure apps

      _configure_sdl2(name, sdl_path)
      _configure_sdl2_image(name, sdl_path,  sdl_image_path) if options[:enable_sdl_image]
      _configure_sdl2_ttf(name, sdl_path, sdl_ttf_path) if options[:enable_sdl_ttf]
      _configure_sdl2_mixer(name, sdl_path, sdl_mixer_path) if options[:enable_sdl_mixer]

      _configure_mruby(name, mruby_path, options.dup)
    end

    def _skel_root(path = nil)
      spec = Gem::Specification.find_by_name("muruby")
      spec.gem_dir unless path
      if path
        File.join(spec.gem_dir, 'skel', path)
      else
        File.join(spec.gem_dir, 'skel')
      end
    end
  end
  
  class Android < Thor
    include Thor::Actions
  
    def self.source_root
      File.dirname(__FILE__)
    end
  end
  

  class Gnu < Thor
    include Thor::Actions
    def self.source_root
      File.dirname(__FILE__)
    end
  end
  
end
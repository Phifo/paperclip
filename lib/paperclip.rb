# Paperclip allows file attachments that are stored in the filesystem. All graphical
# transformations are done using the Graphics/ImageMagick command line utilities and
# are stored in-memory until the record is saved. Paperclip does not require a
# separate model for storing the attachment's information, and it only requires two
# columns per attachment.
#
# Author:: Jon Yurek
# Copyright:: Copyright (c) 2007 thoughtbot, inc.
# License:: Distrbutes under the same terms as Ruby
#
# See the +has_attached_file+ documentation for more details.

module Thoughtbot #:nodoc:
  # Paperclip defines an attachment as any file, though it makes special considerations
  # for image files. You can declare that a model has an attached file with the
  # +has_attached_file+ method:
  #
  #   class User < ActiveRecord::Base
  #     has_attached_file :avatar, :thumbnails => { :thumb => "100x100" }
  #   end
  #
  # See the +has_attached_file+ documentation for more details.
  module Paperclip
    
    PAPERCLIP_OPTIONS = {
      :whiny_deletes    => false,
      :whiny_thumbnails => true
    }
    
    def self.options
      PAPERCLIP_OPTIONS
    end
    
    DEFAULT_ATTACHMENT_OPTIONS = {
      :path_prefix       => ":rails_root/public",
      :url_prefix        => "",
      :path              => ":class/:id/:style_:name",
      :attachment_type   => :image,
      :thumbnails        => {},
      :delete_on_destroy => true
    }
    
    class ThumbnailCreationError < StandardError; end #:nodoc
    class ThumbnailDeletionError < StandardError; end #:nodoc

    module ClassMethods
      # == Methods
      # +has_attached_file+ attaches a file (or files) with a given name to a model. It creates seven instance
      # methods using the attachment name (where "attachment" in the following is the name
      # passed in to +has_attached_file+):
      # * attachment:  Returns the name of the file that was attached, with no path information.
      # * attachment?: Alias for _attachment_ for clarity in determining if the attachment exists.
      # * attachment=(file): Sets the attachment to the file and creates the thumbnails (if necessary).
      #   +file+ can be anything normally accepted as an upload (+StringIO+ or +Tempfile+) or a +File+
      #   if it has had the +Upfile+ module included.
      #   Note this does not save the attachments.
      #     user.avatar = File.new("~/pictures/me.png")
      #     user.avatar = params[:user][:avatar] # When :avatar is a file_field
      # * attachment_file_name(style = :original): The name of the file, including path information. Pass in the
      #   name of a thumbnail to get the path to that thumbnail.
      #     user.avatar_file_name(:thumb) # => "public/users/44/thumb/me.png"
      #     user.avatar_file_name         # => "public/users/44/original/me.png"
      # * attachment_url(style = :original): The public URL of the attachment, suitable for passing to +image_tag+
      #   or +link_to+. Pass in the name of a thumbnail to get the url to that thumbnail.
      #     user.avatar_url(:thumb) # => "http://assethost.com/users/44/thumb/me.png"
      #     user.avatar_url         # => "http://assethost.com/users/44/original/me.png"
      # * attachment_valid?: If unsaved, returns true if all thumbnails have data (that is,
      #   they were successfully made). If saved, returns true if all expected files exist and are
      #   of nonzero size.
      # * destroy_attachment(complain = false): Deletes the attachment and all thumbnails. Sets the +attachment_file_name+
      #   column and +attachment_content_type+ column to +nil+. Set +complain+ to true to override
      #   the +whiny_deletes+ option.
      #
      # == Options
      # There are a number of options you can set to change the behavior of Paperclip.
      # * +path_prefix+: The location of the repository of attachments on disk. See Interpolation below
      #   for more control over where the files are located.
      #     :path_prefix => ":rails_root/public"
      #     :path_prefix => "/var/app/repository"
      # * +url_prefix+: The root URL of where the attachment is publically accessible. See Interpolation below
      #   for more control over where the files are located.
      #     :url_prefix => "/"
      #     :url_prefix => "/user_files"
      #     :url_prefix => "http://some.other.host/stuff"
      # * +path+: Where the files are stored underneath the +path_prefix+ directory and underneath the +url_prefix+ URL.
      #   See Interpolation below for more control over where the files are located.
      #     :path => ":class/:style/:id/:name" # => "users/original/13/picture.gif"
      # * +attachment_type+: If this is set to :image (which it is, by default), Paperclip will attempt to make thumbnails.
      # * +thumbnails+: A hash of thumbnail styles and their geometries. You can find more about geometry strings
      #   at the ImageMagick website (http://www.imagemagick.org/script/command-line-options.php#resize). Paperclip
      #   also adds the "#" option, which will resize the image to fit maximally inside the dimensions and then crop
      #   the rest off (weighted at the center).
      # * +delete_on_destroy+: When records are deleted, the attachment that goes with it is also deleted. Set
      #   this to +false+ to prevent the file from being deleted.
      #
      # == Interpolation
      # The +path_prefix+, +url_prefix+, and +path+ options can have dynamic interpolation done so that the 
      # locations of the files can vary depending on a variety of factors. Each variable looks like a Ruby symbol
      # and is searched for with +gsub+, so a variety of effects can be achieved. The list of possible variables
      # follows:
      # * +rails_root+: The value of the +RAILS_ROOT+ constant for your app. Typically used when putting your
      #   attachments into the public directory. Probably not useful in the +path+ definition.
      # * +class+: The underscored, pluralized version of the class in which the attachment is defined.
      # * +attachment+: The pluralized name of the attachment as given to +has_attached_file+
      # * +style+: The name of the thumbnail style for the current thumbnail. If no style is given, "original" is used.
      # * +id+: The record's id.
      # * +name+: The file's name, as stored in the attachment_file_name column.
      #
      # When interpolating, you are not confined to making any one of these into its own directory. This is
      # perfectly valid:
      #   :path => ":attachment/:style/:id-:name" # => "avatars/thumb/44-me.png"
      #
      # == Model Requirements
      # For any given attachment _foo_, the model the attachment is in needs to have both a +foo_file_name+
      # and +foo_content_type+ column, as a type of +string+. The +foo_file_name+ column contains only the name
      # of the file and none of the path information. However, the +foo_file_name+ column accessor is overwritten
      # by the one (defined above) which returns the full path to whichever style thumbnail is passed in.
      # In a pinch, you can either use +read_attribute+ or the plain +foo+ accessor, which returns the database's
      # +foo_file_name+ column.
      #
      # == Event Triggers
      # When an attachment is set by using he setter (+model.attachment=+), the thumbnails are created and held in
      # memory. They are not saved until the +after_save+ trigger fires, at which point the attachment and all
      # thumbnails are written to disk.
      #
      # Attached files are destroyed when the associated record is destroyed in a +before_destroy+ trigger. Set
      # the +delete_on_destroy+ option to +false+ to prevent this behavior. Also note that using the ActiveRecord's
      # +delete+ method instead of the +destroy+ method will prevent the +before_destroy+ trigger from firing.
      def has_attached_file *attachment_names
        options = attachment_names.last.is_a?(Hash) ? attachment_names.pop : {}
        options = DEFAULT_ATTACHMENT_OPTIONS.merge(options)

        include InstanceMethods
        attachments ||= {}

        attachment_names.each do |attr|
          attachments[attr] = (attachments[attr] || {:name => attr}).merge(options)

          define_method "#{attr}=" do |uploaded_file|
            return unless is_a_file? uploaded_file
            attachments[attr].merge!({
              :dirty        => true,
              :files        => {:original => uploaded_file},
              :content_type => uploaded_file.content_type,
              :filename     => sanitize_filename(uploaded_file.original_filename)
            })
            write_attribute(:"#{attr}_file_name", attachments[attr][:filename])
            write_attribute(:"#{attr}_content_type", attachments[attr][:content_type])
            
            if attachments[attr][:attachment_type] == :image
              attachments[attr][:thumbnails].each do |style, geometry|
                attachments[attr][:files][style] = make_thumbnail(attachments[attr][:files][:original], geometry)
              end
            end

            uploaded_file
          end
          
          define_method attr do
            read_attribute("#{attr}_file_name")
          end
          alias_method "#{attr}?", attr
          
          define_method "#{attr}_attachment" do
            attachments[attr]
          end
          private "#{attr}_attachment"
          
          define_method "#{attr}_file_name" do |*args|
            style = args.shift || :original # This prevents arity warnings
            read_attribute("#{attr}_file_name") ? path_for(attachments[attr], style) : ""
          end
          
          define_method "#{attr}_url" do |*args|
            style = args.shift || :original # This prevents arity warnings
            read_attribute("#{attr}_file_name") ? url_for(attachments[attr], style) : ""
          end
          
          define_method "#{attr}_valid?" do
            attachments[attr][:thumbnails].all? do |style, geometry|
              attachments[attr][:dirty] ?
                !attachments[attr][:files][style].blank? :
                File.file?( path_for(attachments[attr], style))
            end
          end
          
          define_method "destroy_#{attr}" do |*args|
            complain = args.first || false
            if attachments[attr].keys.any?
              delete_attachment attachments[attr], complain
            end
          end

          define_method "#{attr}_after_save" do
            if attachments[attr].keys.any?
              write_attachment attachments[attr] if attachments[attr][:files]
              attachments[attr][:dirty] = false
              attachments[attr][:files] = nil
            end
          end
          private :"#{attr}_after_save"
          after_save :"#{attr}_after_save"
          
          define_method "#{attr}_before_destroy" do
            if attachments[attr].keys.any?
              delete_attachment attachments[attr] if attachments[attr][:delete_on_destroy]
            end
          end
          private :"#{attr}_before_destroy"
          before_destroy :"#{attr}_before_destroy"
        end
      end
    end

    module InstanceMethods #:nodoc:
      private
      def interpolate attachment, prefix_type, style
        returning "#{attachment[prefix_type]}/#{attachment[:path]}" do |prefix|
          prefix.gsub!(/:rails_root/, RAILS_ROOT)
          prefix.gsub!(/:id/, self.id.to_s) if self.id
          prefix.gsub!(/:class/, self.class.to_s.underscore.pluralize)
          prefix.gsub!(/:style/, style.to_s)
          prefix.gsub!(/:attachment/, attachment[:name].to_s.pluralize)
          prefix.gsub!(/:name/, attachment[:filename])
        end
      end
      
      def path_for attachment, style = :original
        file = read_attribute("#{attachment[:name]}_file_name")
        return nil unless file
         
        prefix = interpolate attachment, :path_prefix, style
        File.join( prefix.split("/").reject(&:blank?) )
      end
      
      def url_for attachment, style = :original
        file = read_attribute("#{attachment[:name]}_file_name")
        return nil unless file
         
        interpolate attachment, :url_prefix, style
      end
      
      def ensure_directories_for attachment
        attachment[:files].each do |style, file|
          dirname = File.dirname(path_for(attachment, style))
          FileUtils.mkdir_p dirname
        end
      end
      
      def write_attachment attachment
        ensure_directories_for attachment
        attachment[:files].each do |style, atch|
          File.open( path_for(attachment, style), "w" ) do |file|
            atch.rewind
            file.write(atch.read)
          end
        end
      end
      
      def delete_attachment attachment, complain = false
        (attachment[:thumbnails].keys + [:original]).each do |style|
          file_path = path_for(attachment, style)
          begin
            FileUtils.rm(file_path)
          rescue Errno::ENOENT
            raise ThumbnailDeletionError if ::Thoughtbot::Paperclip.options[:whiny_deletes] || complain
          end
        end
        self.update_attribute "#{attachment[:name]}_file_name", nil
        self.update_attribute "#{attachment[:name]}_content_type", nil
      end

      def make_thumbnail orig_io, geometry
        operator = geometry[-1,1]
        geometry, crop_geometry = geometry_for_crop(geometry, orig_io) if operator == '#'
        command = "convert - -scale '#{geometry}' #{operator == '#' ? "-crop '#{crop_geometry}'" : ""} -"
        thumb = IO.popen(command, "w+") do |io|
          orig_io.rewind
          io.write(orig_io.read)
          io.close_write
          StringIO.new(io.read)
        end
        if ::Thoughtbot::Paperclip.options[:whiny_thumbnails]
          raise ThumbnailCreationError, "Convert returned with result code #{$?.exitstatus}." unless $?.success?
        end
        thumb
      end
      
      def geometry_for_crop geometry, orig_io
        IO.popen("identify -", "w+") do |io|
          orig_io.rewind
          io.write(orig_io.read)
          io.close_write
          if match = io.read.split[2].match(/(\d+)x(\d+)/)
            src   = match[1,2].map(&:to_f)
            srch  = src[0] > src[1]
            dst   = geometry.match(/(\d+)x(\d+)/)[1,2].map(&:to_f)
            dsth  = dst[0] > dst[1]
            ar    = src[0] / src[1]
            
            scale_geometry, scale = if dst[0] == dst[1]
              if srch
                [ "x#{dst[1]}", src[1] / dst[1] ]
              else
                [ "#{dst[0]}x", src[0] / dst[0] ]
              end
            elsif dsth
              [ "#{dst[0]}x", src[0] / dst[0] ]
            else
              [ "x#{dst[1]}", src[1] / dst[1] ]
            end
            
            crop_geometry = if dsth
              "%dx%d+%d+%d" % [ dst[0], dst[1], 0, (src[1] / scale - dst[1]) / 2 ]
            else
              "%dx%d+%d+%d" % [ dst[0], dst[1], (src[0] / scale - dst[0]) / 2, 0 ]
            end
            
            [ scale_geometry, crop_geometry ]
          end
        end
      end
      
      def is_a_file? data
        [:size, :content_type, :original_filename, :read].map do |meth|
          data.respond_to? meth
        end.all?
      end

      def sanitize_filename filename
        File.basename(filename).gsub(/[^\w\.\_]/,'_')
      end
      protected :sanitize_filename
    end
    
    # The Upfile module is a convenience module for adding uploaded-file-type methods
    # to the +File+ class. Useful for testing.
    #   user.avatar = File.new("test/test_avatar.jpg")
    module Upfile
      # Infer the MIME-type of the file from the extension.
      def content_type
        type = self.path.match(/\.(\w+)$/)[1]
        case type
        when "jpg", "png", "gif" then "image/#{type}"
        when "txt", "csv", "xml", "html", "htm" then "text/#{type}"
        else "x-application/#{type}"
        end
      end
      
      # Returns the file's normal name.
      def original_filename
        self.path
      end
      
      # Returns the size of the file.
      def size
        File.size(self)
      end
    end
  end
end
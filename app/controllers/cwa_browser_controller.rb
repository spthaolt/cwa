class CwaBrowserController < ApplicationController
  respond_to :json
  require 'digest/sha2'

  def index
    @project = Project.find(params[:project_id])
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?
    @groups = CwaGroups.new
    @group_list = @groups.that_i_manage + @groups.member_of

    Rails.logger.debug "CwaBrowserController::index() => #{params[:share]} #{params[:dir]}"

    begin 
      @browser = CwaBrowser.new params[:share], params[:dir]
    rescue Exception => e
      flash[:error] = e.message
      @browser = CwaBrowser.new "home", nil
    end 

    respond_to do |format|
      format.html
    end
  end

  # Change file name
  def rename
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    file = resolve_path(params[:share], params[:file])
    new_file = resolve_path(params[:share], params[:new_name])
    Rails.logger.debug "Redmine::CwaBrowserHelper.rename() => #{file} #{new_file}"

    if Redmine::CwaBrowserHelper.rename(file, new_file)
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :result => result }.to_json, :status => code }
    end

  end

  # create a directory
  def mkdir 
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    if params[:path] == nil
      new_dir = resolve_path(params[:share], "/" + params[:new_dir])
    else 
      new_dir = resolve_path(params[:share], params[:path] + "/" + params[:new_dir])
    end

    if Redmine::CwaBrowserHelper.mkdir(new_dir)
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :result => result }.to_json, :status => code }
    end

  end

  # Create a text file
  def create
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    if params[:path] == nil
      new_file = resolve_path(params[:share], "/" + params[:new_file_name])
    else 
      new_file = resolve_path(params[:share], params[:path] + "/" + params[:new_file_name])
    end

    if params[:new_file_content] != nil and new_file != nil
      upload = params["file"]
      file = Redmine::CwaBrowserHelper::Put.new(new_file)
      if file
        file.write(params[:new_file_content])
        file.done
      else
        flash[:error] = "Could not store file \"#{new_file}\""
      end
    else
      flash[:error] = "New document name/content cannot be blank"
    end
    redirect_to :action => "index", :share => params[:share], :dir => params[:path]
  end

  # Delete file/directory from :browse_path
  def delete
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    Rails.logger.debug "Redmine::CwaBrowserController.delete() :: #{params[:share]} #{params[:path]}"

    item = resolve_path(params[:share], params[:path])
    if Redmine::CwaBrowserHelper.delete(item)
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :result => result }.to_json, :status => code }
    end
  end

  # Upload file and store
  def upload
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    upload = params["file"]

    if params[:path] != nil
      dir = resolve_path(params[:share], "/" + params[:path])
    else 
      dir = resolve_path(params[:share], nil)
    end

    file = Redmine::CwaBrowserHelper::Put.new(dir + "/" + upload.original_filename) or
      flash[:error] = "Could not store file(s) #{dir}/#{upload.original_filename}"

    if file
      while (data = upload.read(1024*128)) != nil
        file.write(data)
      end
      file.done

      flash[:notice] = "File \"#{upload.original_filename}\" successfully upload!"
    else
      flash[:error] = "File \"#{upload.original_filename}\" failed to upload!"
    end

    redirect_to :action => 'index', :share => params[:share], :dir => params[:path]
  end

  def tail
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?
    text = ""

    file = resolve_path(params[:share], params[:file])

    Rails.logger.debug "CwaBrowserController::tail() => #{file}"

    type = Redmine::CwaBrowserHelper.type(file)

    if type !~ /^text\/.*/
      text = "Cannot tail file!  It is not a text file!"
    else
      file = Redmine::CwaBrowserHelper.tail(file)
      Rails.logger.debug "CwaBrowserController.tail() => Im in here! #{file}"

      file.each_tail do |data|
        text += data
      end
    end

    render :text => text
  end

  # Since we can get content using a POST then directing to a new window for download,
  # lets set up a SHA512 file id, pass it back to the client, then use a GET, referencing the
  # fid, to trigger the download
  def download
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    file = resolve_path(params[:share], params[:path])
    
    fid = Digest::SHA512.hexdigest("RandomSaltiness" + file)

    Rails.cache.fetch(fid, :expires_in => 60.seconds) do
      file
    end

    type = Redmine::CwaBrowserHelper.type(file)

    if fid && type
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :result => result, :fid => fid, :type => type }.to_json, :status => code }
    end
  end     

  # Download file from fid
  def get
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    file = Rails.cache.fetch(params[:fid])

    self.response.headers["Content-Type"] = "application/octet-stream"
    self.response.headers["Content-Disposition"] = "attachment; filename=#{file.split('/').last}"
    self.response.headers["Content-Length"] = Redmine::CwaBrowserHelper.file_size(file).to_s
    self.response.headers['Last-Modified'] = Time.now.ctime.to_s
    self.response.headers['Accept-Ranges'] = "bytes"

    self.response_body = Redmine::CwaBrowserHelper::Retrieve.new(file)
  end
  
  # Download zip file archive of directory
  def get_zip
    @user = CwaIpaUser.new
    (redirect_to :controller => 'cwa_default', :action => 'not_activated' and return) if !@user.provisioned?

    file = Rails.cache.fetch(params[:fid])
    
    self.response.headers["Content-Type"] = "application/octet-stream"
    self.response.headers["Content-Disposition"] = "attachment; filename=#{file.split('/').last}.zip"
    self.response.headers['Last-Modified'] = Time.now.ctime.to_s
    self.response.headers['Accept-Ranges'] = "bytes"

    self.response_body = Redmine::CwaBrowserHelper::RetrieveZip.new(file)
  end

  private
  def resolve_path(share,path)

    if path != nil
      case share
      when "home"
        file = @user.homedirectory + "/" + path
      when "work"
        file = @user.workdirectory + "/" + path
      when "shares"
        file = "/shares/" + path
      end
    else
      case share
      when "home"
        file = @user.homedirectory
      when "work"
        file = @user.workdirectory
      when "shares"
        file = nil
      end
    end
    file
  end
    
    

end

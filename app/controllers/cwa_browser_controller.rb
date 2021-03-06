class CwaBrowserController < ApplicationController
  respond_to :json
  require 'digest/sha2'
  include CwaIpaAuthorize

  before_filter :find_project, :authorize, :ipa_authorize
  accept_api_auth :index, :mkdir, :rename, :delete, :download, :get, :upload, :move, :copy, :op_status

  def index
    @groups = CwaGroups.new
    @group_list = @groups.that_i_manage + @groups.member_of

    begin 
      @browser = CwaBrowser.new params[:share], params[:dir], @ipa_user
    rescue Exception => e
      flash[:error] = e.message
      @browser = CwaBrowser.new "home", nil, @ipa_user
    end 

    respond_to do |format|
      format.html
      format.json { 
        render :json => e.nil? ? { 
          :response => "success",
          :files => @browser.files, 
          :error => nil,
          :directories => @browser.directories
        } : {
          :response => "failure",
          :files => nil,
          :error => e.message,
          :directories => nil
        }
      }
    end
  end

  # Change file name
  def rename
    file = resolve_path(params[:share], params[:file])
    new_file = resolve_path(params[:share], params[:new_name])

    if Redmine::CwaBrowserHelper.rename(file, new_file)
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :response => result }, :status => code }
    end
  end

  # create a directory
  def mkdir 
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
      format.json { render :json => { :response => result }, :status => code }
    end

  end

  # Create a text file
  def create
    if params[:path] == nil
      new_file = resolve_path(params[:share], "/" + params[:new_file_name])
    else 
      new_file = resolve_path(params[:share], params[:path] + "/" + params[:new_file_name])
    end

    if params[:new_file_content] != nil and new_file != nil
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
    item = resolve_path(params[:share], params[:path])
    if Redmine::CwaBrowserHelper.delete(item)
      result = 'success'
      code = 200
    else
      result = 'failure'
      code = 400
    end

    respond_to do |format|
      format.json { render :json => { :response => result }, :status => code }
    end
  end

  # Upload file and store
  def upload
    upload = params["upload_file"]

    if params[:dir] != nil
      dir = resolve_path(params[:share], "/" + params[:dir])
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
    respond_to do |format|
      format.html { redirect_to :action => 'index', :share => params[:share], :dir => params[:dir] }
      format.json { render :json => {} }
    end
  end

  def tail
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
    file = resolve_path(params[:share], params[:path])
    
    fid = Digest::SHA512.hexdigest("RandomSaltiness" + (Time.now.to_i+Time.now.tv_usec+Time.now.tv_nsec).to_s + file)

    Rails.cache.fetch(fid, :expires_in => 60.seconds) do
      { :user => @user.login, :path => file }
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
      format.json { render :json => { :response => result, :fid => fid, :type => type }, :status => code }
    end
  end     

  # Download file from fid
  def get
    file = nil
    file_blob = Rails.cache.fetch(params[:fid])

    if file_blob[:user] == @user.login
      file = file_blob[:path]
    else
      return
    end

    self.response.headers["Content-Type"] = "application/octet-stream"
    self.response.headers["Content-Disposition"] = "attachment; filename=#{file.split('/').last}"
    self.response.headers["Content-Length"] = Redmine::CwaBrowserHelper.file_size(file).to_s
    self.response.headers['Last-Modified'] = Time.now.ctime.to_s
    self.response.headers['Accept-Ranges'] = "bytes"

    self.response_body = Redmine::CwaBrowserHelper::Retrieve.new(file)
  end
  
  # Download zip file archive of directory
  def get_zip

    file = nil
    file_blob = Rails.cache.fetch(params[:fid])

    if file_blob[:user] == @user.login
      file = file_blob[:path]
    else
      return
    end
    
    self.response.headers["Content-Type"] = "application/octet-stream"
    self.response.headers["Content-Disposition"] = "attachment; filename=#{file.split('/').last}.zip"
    self.response.headers['Last-Modified'] = Time.now.ctime.to_s
    self.response.headers['Accept-Ranges'] = "bytes"

    self.response_body = Redmine::CwaBrowserHelper::RetrieveZip.new(file)
  end

  def move
    path = resolve_path(params[:share], params[:path])
    target_path = resolve_path(params[:target_share], params[:target_path])
    response = {}

    # Check to see if shares match.  If so, simple mv will do
    if params[:share] == params[:target_share]
      # use rename, its just the mv command
      if Redmine::CwaBrowserHelper.rename(path, target_path)
        response[:status] = "success"
        response[:code] = 200
      else
        response[:status] = "failure"
        response[:code] = 500
      end
    else
      # Now we have to kick off an asynchronous task that feeds data to a cache
      # based on the hash of the transfer components
      t = ThreadTracker.new do
        Redmine::CwaBrowserHelper.remoteMove(path, target_path)
      end
      
      # Then we have to send back a JSON response to signal the beginning of the transfer
      response[:status] = "started"
      response[:code] = 200
      response[:move_id] = t.opid
    end
  
    respond_to do |format|
      format.json { render :json => response }
    end
  end

  def copy
    path = resolve_path(params[:share], params[:path])
    target_path = resolve_path(params[:target_share], params[:target_path])
    response = {}

    # pop this in the background and track it
    t = ThreadTracker.new do
      Redmine::CwaBrowserHelper.copy(path, target_path)
    end
      
    # Then we have to send back a JSON response to signal the beginning of the transfer
    response[:status] = "started"
    response[:code] = 200
    response[:copy_id] = t.opid
  
    respond_to do |format|
      format.json { render :json => response }
    end
  end

  # That's pretty easy.  Just check the status of the thread from the cache
  def op_status
    # invoke the threadtracker garbage collector
    ThreadTracker.gc
    op_hash = {}
    ops = ThreadTracker.my_ops

    Rails.logger.debug "OP_STATUS: #{ops.to_s}"

    if !ops.nil? && ops.length > 0
      ops.each { |op| op_hash.merge!(ThreadTracker.cache_status(op)) }
    else
      op_hash = nil
    end

    respond_to do |format|
      format.json { render :json => op_hash }
    end
  end
    
  private
  def resolve_path(share,path)

    if path != nil
      case share
      when "home"
        file = @ipa_user.homedirectory + "/" + path
      when "work"
        file = @ipa_user.workdirectory + "/" + path
      when "shares"
        file = "/shares/" + path
      end
    else
      case share
      when "home"
        file = @ipa_user.homedirectory
      when "work"
        file = @ipa_user.workdirectory
      when "shares"
        file = nil
      end
    end
    file
  end
    
  def find_project    
    @project = Project.find(params[:project_id])
  end

end

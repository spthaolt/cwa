class CwaGroupsController < ApplicationController
  unloadable

  include CwaIpaAuthorize

  before_filter :find_project, :authorize, :ipa_authorize

  # Load the default view
  def index
    @groups = CwaGroups.new
    respond_to do |format|
      format.html
    end
  end

  def groups
    @gs = CwaGroups.new
    respond_to do |format|
      format.html
    end
  end

  def show
    @gs = CwaGroups.new
    respond_to do |format|
      format.html
    end
  end

  def create 
    respond_to do |format|
      format.html
    end
  end

  # Create group
  def create_group
    @groups = CwaGroups.new

    if params[:group_name] !~ ::CwaConstants::GROUP_REGEX
      flash[:error] = "The group name you entered is invalid!"
      redirect_to :action => :create
      return
    end

    if @groups.that_i_manage.length < ::CwaConstants::GROUP_MAX
      if @groups.create({ :owner => @user.login, :group_name => params[:group_name], :desc => params[:desc] })
        flash[:notice] = "Your group \"#{params[:group_name]}\" has been created!"
      else
        flash[:error] = "Could not create group \"#{params[:group_name]}\".  Name is already taken!"
        redirect_to :action => :create
        return
      end
    else
      flash[:error] = "You've reached the maximum #{::CwaConstants::GROUP_MAX} group limitation.  You can't have any more!"
    end
    redirect_to :action => :index, :project_id => params[:project_id]
  end

  def delete_group
    @groups = CwaGroups.new
    if @groups.delete params[:group_name]
      flash[:notice] = "Group \"#{params[:group_name]}\" deleted!"
    else
      flash[:error] = "Unable to delete group \"#{params[:group_name]}\"!"
    end
    redirect_to :action => :index, :project_id => params[:project_id]
  end

  # Add a user to a group
  def add
    @groups = CwaGroups.new

    user_name_regex = /^[a-zA-Z0-9-]{3,20}$/

    if params[:user_name] !~ ::CwaConstants::USER_REGEX
      flash[:error] = "You entered an invalid username!"
      redirect_to :action => :show, :group_name => params[:group_name]
      return
    end

    if @groups.add_to_my_group(params[:user_name], params[:group_name])
      CwaMailer.group_add_member(params[:user_name], params[:group_name]).deliver
      flash[:notice] = "\"#{params[:user_name]}\" has been added to \"#{params[:group_name]}\""
    else
      flash[:error] = "There was a problem adding \"#{params[:user_name]}\" to \"#{params[:group_name]}\".  The user probably does not exist."
    end
    redirect_to :action => :show, :group_name => params[:group_name], :project_id => params[:project_id]
  end

  # Delete a user from a group
  def delete
    @groups = CwaGroups.new

    if params[:user_name]
      if @groups.delete_from_my_group(params[:user_name], params[:group_name])
        CwaMailer.group_remove_member(User.find_by_login(params[:user_name]), params[:group_name]).deliver
        flash[:notice] = "\"#{params[:user_name]}\" has been removed from \"#{params[:group_name]}\""
      else
        flash[:error] = "There was a problem removing \"#{params[:user_name]}\" from \"#{params[:group_name]}\""
      end
    else
      if @groups.delete_me_from_group params[:group_name]
        flash[:notice] = "You have been removed from group \"#{params[:group_name]}\""
      else
        flash[:error] = "There was a problem removing you from group \"#{params[:group_name]}\""
      end
    end
    redirect_to :action => :show, :group_name => params[:group_name], :project_id => params[:project_id]
  end

  def disband
    groups = CwaGroups.new

    if groups.delete(params[:group_name])
      flash[:notice] = "\"#{params[:group_name]}\" has been disbanded!"
    else
      flash[:error] = "Problem disbanding \"#{params[:group_name]}\""
    end
    redirect_to :action => :index, :project_id => params[:project_id]
  end

  def delete_request
    # Re-direct to unavailable page
    if params[:project_id] != Redmine::Cwa.project_id 
      redirect_to :controller => 'cwa_default', :action => 'unavailable'
      return
    end 

    groups = CwaGroups.new
    request = CwaGroupRequests.find_by_id(params[:request_id])
    group_name = groups.by_id(request.group_id)[:cn]

    if request.delete
      flash[:notice] = "Request to join \"#{group_name}\" removed."
    else
      flash[:error] = "There was a problem removing your request to join \"#{group_name}\""
    end
    redirect_to :action => :index, :project_id => params[:project_id]
  end

  def allow_join
    groups = CwaGroups.new
    request = CwaGroupRequests.find_by_id(params[:request_id])
    group_name = groups.by_id(request.group_id)[:cn]
    user_name = User.find_by_id(request.user_id).login

    if groups.add_to_my_group(user_name, group_name)
      request.delete
      CwaMailer.group_add_member(user_name, group_name).deliver
      flash[:notice] = "User #{user_name} added to group #{group_name}!"
    else
      flash[:error] = "Problem adding #{user_name} to group #{group_name}!"
    end
    redirect_to :action => :index, :project_id => params[:project_id]
  end
      
  # store request to join group
  def save_request
    @groups = CwaGroups.new
    if CwaGroupRequests.find(:first, :conditions => ["group_id = ? and user_id = ?", params[:gidnumber], @user.id])
      flash[:error] = "You've already requested to join this group!"
    else
      req = CwaGroupRequests.create do |r|
        r.group_id = params[:gidnumber]
        r.user_id  = @user.id
      end

      group_name = @groups.by_id(params[:gidnumber])[:cn]
      group_owner = User.find_by_login(@groups.by_id(params[:gidnumber])[:owner])

      if req
        CwaMailer.group_member_request(group_owner, group_name).deliver
        flash[:notice] = "Your request to join #{params[:group_name]} has been registered!"
      else
        flash[:error] = "There was a problem registering your request to join  #{params[:group_name]}!"
      end
    end
    redirect_to :action => 'index', :project_id => params[:project_id]
  end
  
  private
  def find_project
    @project = Project.find(params[:project_id])
  end
end

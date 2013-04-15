class AutoWatchFiltersController < ApplicationController
  unloadable
  include QueriesHelper
  helper :queries

  def new
    @project = Project.visible.find(:first, :conditions => {:identifier => params[:project_id]})
    @auto_watch_filter = AutoWatchFilter.new(params[:auto_watch_filter])
    @groups = Group.find(:all, :order => 'lastname')
    @auto_watch_filter.project_id = @project.id

    @auto_watch_filter.add_filters(params[:fields] || params[:f], params[:operators] || params[:op], params[:values] || params[:v]) if params[:fields] || params[:f]

    if request.post? && params[:confirm] && @auto_watch_filter.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to :controller => :projects, :action => :settings, :tab => "auto_watch_filters", :id => @project
      return
    end
    render :layout => false if request.xhr?
  end

  def edit
    @auto_watch_filter = AutoWatchFilter.find(params[:id])
    @project = Project.visible.find(:first, :conditions => {:identifier => params[:project_id]})
    @groups = Group.find(:all, :order => 'lastname')

    if request.post?
      @auto_watch_filter.filters = {}
      @auto_watch_filter.add_filters(params[:fields] || params[:f], params[:operators] || params[:op], params[:values] || params[:v]) if params[:fields] || params[:f]
      @auto_watch_filter.attributes = params[:auto_watch_filter]

      if @auto_watch_filter.save
        flash[:notice] = l(:notice_successful_update)
        redirect_to :controller => :projects, :action => :settings, :tab => "auto_watch_filters", :id => @project
      end
    end

  end

  def destroy
    @auto_watch_filter = AutoWatchFilter.find(params[:id])
    @project = Project.visible.find(:first, :conditions => {:identifier => params[:project_id]})
    @auto_watch_filter.destroy if request.post?
    redirect_to :controller => :projects, :action => :settings, :tab => "auto_watch_filters", :id => @project
  end
end

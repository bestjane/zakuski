class CustomSearchEnginesController < ApplicationController
  before_filter :initialize_cses
  before_filter :authenticate_user!, only: [:new, :create, :edit, :update, 
                                      :destroy, :share, :clone]
  before_filter :correct_user, only: [:edit, :update, :share, :destroy]
  before_filter :only_publish_cse_available, only: [:show]
  #before_filter :admin_user, only: [:destroy]
  
  # GET /custom_search_engines
  # GET /custom_search_engines.json
  def index
    respond_to do |format|
      format.html # index.html.erb
    end
  end

  # GET /custom_search_engines/1
  # GET /custom_search_engines/1.json
  def show
    @filter_annotations = @custom_search_engine.annotations.find_all{|a| a.mode == 'filter'}
    @exclude_annotations = @custom_search_engine.annotations.find_all{|a| a.mode == 'exclude'}
    @boost_annotations = @custom_search_engine.annotations.find_all{|a| a.mode == 'boost'}
    
    respond_to do |format|
      format.html # show.html.erb
      format.json { render json: @custom_search_engine }
      format.xml
    end
  end

  # GET /custom_search_engines/new
  # GET /custom_search_engines/new.json
  def new
    @custom_search_engine = CustomSearchEngine.new
    @custom_search_engine.specification = Specification.new
    @custom_search_engine.annotations = [Annotation.new]
    @custom_search_engine.node = Node.find(params[:node_id])
    
    respond_to do |format|
      format.html # new.html.erb
      format.json { render json: @custom_search_engine }
    end
  end

  # GET /custom_search_engines/1/edit
  def edit
    @custom_search_engine = CustomSearchEngine.find(params[:id])
  end

  # POST /custom_search_engines
  # POST /custom_search_engines.json
  def create
    @custom_search_engine = CustomSearchEngine.new(params[:custom_search_engine])
    @custom_search_engine.author = current_user
    @custom_search_engine.status = 'draft'
    respond_to do |format|
      if @custom_search_engine.save
        add_cse_to_dashboard(@custom_search_engine)
        link_cse(@custom_search_engine)
        flash[:success] = I18n.t('human.success.create', item: I18n.t('human.text.cse'))
        format.html { redirect_to cse_path(@custom_search_engine)}
        format.json { render json: @custom_search_engine, status: :created, location: @custom_search_engine }
      else
        format.html { render action: "new" }
        format.json { render json: @custom_search_engine.errors, status: :unprocessable_entity }
      end
    end
  end

  # PUT /custom_search_engines/1
  # PUT /custom_search_engines/1.json
  def update
    respond_to do |format|
      if @custom_search_engine.update_attributes(params[:custom_search_engine])
        flash[:success] = I18n.t('human.success.update', item: I18n.t('human.text.cse'))
        format.html { redirect_to cse_path(@custom_search_engine) }
        format.json { head :no_content }
      else
        format.html { render action: "edit" }
        format.json { render json: @custom_search_engine.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /custom_search_engines/1
  # DELETE /custom_search_engines/1.json
  def destroy
    @custom_search_engine = CustomSearchEngine.find(params[:id])
    @custom_search_engine.destroy

    respond_to do |format|
      format.html { redirect_to cses_url }
      format.json { head :no_content }
    end
  end

  # GET /search
  def search
    respond_to do |format|
      format.html
    end
  end

  # GET /q/:query
  def query
    @query = params[:query]
    respond_to do |format|
      format.html
    end
  end

  # GET /cses/:id/keep
  def keep
    @custom_search_engine = CustomSearchEngine.find(params[:id])
    
    if @keeped_cses.include?(@custom_search_engine)
      @error = I18n.t('human.errors.already_keep')
    else
      if user_signed_in?
        if current_user == @custom_search_engine.author
          @error = I18n.t('human.errors.keep_own')
        elsif(current_user.keeped_custom_search_engines.push(@custom_search_engine))
          Notification.messager(title: I18n.t('notification.keep', 
            {user: view_context.link_to(current_user.username, 
              user_path(current_user)),
              cse:view_context.link_to(@custom_search_engine.specification.title[0,30],
                cse_path(@custom_search_engine))}),
                                receiver: @custom_search_engine.author,
                                source: 'cse')
        else
          @error = I18n.t('human.errors.general')
        end
      else
        if @keeped_cses.count > 9
          # guests only keep 10 cses at most
          @error = I18n.t('human.errors.limit_cses')
        else
          @keeped_cses.push @custom_search_engine
          cookies[:keeped_cse_ids] += ",#{@custom_search_engine.id}"
        end
      end
    end
    if @error.nil?
      @message = I18n.t('human.success.general')
      add_cse_to_dashboard(@custom_search_engine)
      @custom_search_engine.inc(:keep_count, 1)
    end
    respond_to do |format|
      format.js
    end
  end

  # GET /cses/:id/remove
  def remove
    @custom_search_engine = CustomSearchEngine.find(params[:id])

    if @keeped_cses.include?(@custom_search_engine)
      if user_signed_in?
        current_user.keeped_custom_search_engines.delete(@custom_search_engine)
        current_user.dashboard_custom_search_engines.delete(@custom_search_engine)
      else
        @keeped_cses.delete(@custom_search_engine)
        @dashboard_cses.delete(@custom_search_engine)
        if @keeped_cses.count == 0
          cookies.delete(:keeped_cse_ids)
        else
          cookies[:keeped_cse_ids] = @keeped_cses.map{ |cse| cse.id }.join(',')
        end
        if @dashboard_cses.count == 0
          cookies.delete(:dashboard_cse_ids)
        else
          cookies[:dashboard_cse_ids] = @dashboard_cses.map{ |cse| cse.id }.join(',')
        end
      end
      cookies.delete(:linked_cseid) if(cookies[:linked_cseid] == params[:id])
    else
      @error = I18n.t('human.errors.not_keep');
    end

    if @error.nil?
      @message = I18n.t('human.success.general')
      @custom_search_engine.inc(:keep_count, -1)
    end
    respond_to do |format|
      format.js
    end

  end

  # GET /cses/:id/clone
  def clone
    @custom_search_engine = CustomSearchEngine.find(params[:id])
    if current_user.own_cse?(@custom_search_engine)
      flash[:error] = I18n.t('human.errors.clone') 
    else
      @new = CustomSearchEngine.new
      @new.node = @custom_search_engine.node
      @new.author = current_user
      @new.parent_id = @custom_search_engine.id
      @new.specification = @custom_search_engine.specification
      @new.annotations = @custom_search_engine.annotations
      @new.status = 'draft'
    end

    respond_to do |format|
      if @new.present? && @new.save
        Notification.messager(receiver: @custom_search_engine.author, source: 'cse',
              title: I18n.t('notification.clone', 
                      {user: view_context.link_to(current_user.username, 
                        user_path(current_user)),
                        cse:view_context.link_to(@custom_search_engine.specification.title,
                        cse_path(@custom_search_engine))}))
        add_cse_to_dashboard(@new)
        format.html {redirect_to edit_cse_path(@new)}
      else
        flash[:error] = @new.errors.full_messages
        format.html { redirect_to cse_path(@custom_search_engine) }
      end
    end
  end

  def share
    respond_to do |format|
      @custom_search_engine.status = 'publish'
      if @custom_search_engine.save
        flash[:success] = I18n.t('human.success.publish')
      else
        flash[:error] = @custom_search_engine.errors.full_messages
      end
      format.html {redirect_to cse_path(@custom_search_engine)}
    end
  end

  def consumers
    @custom_search_engine = CustomSearchEngine.find(params[:id])

    if params[:more].nil?
      @more = 10
    else
      @more = params[:more].to_i + 10
    end
    @more_consumers = @custom_search_engine.consumers.slice(@more, 10)

    respond_to do |format|
      format.js
    end
  end

  def dashboard_save
    @new_dashboard_cse_ids = params[:dashboard_cses]
    # & removes the redudent cse
    @new_dashboard_cse_ids &= @new_dashboard_cse_ids
    if @new_dashboard_cse_ids.present?
      @dashboard_cses.clear
      cses_array = (@created_cses | @keeped_cses)
      dashboard_index = 0
      @new_dashboard_cse_ids.each do |id|
        dashboard_index += 1
        cses_array.each do |cse|
          if cse.id.to_s == id
            cse.dashboard_index = dashboard_index
            cse.save
            @dashboard_cses << cse
            break
          end
        end
      end
    else
      @dashboard_cses.clear
    end
    #flash[:error] = @dashboard_cses
    if(user_signed_in?)
      current_user.dashboard_custom_search_engines = @dashboard_cses
    else
      cookies[:dashboard_cse_ids] = @dashboard_cses.map{|cse| cse.id}.join(',')
    end
    flash[:success] = I18n.t('human.success.general')
    respond_to do |format|
      format.html {redirect_to cses_path}
    end
  end

  private
    def correct_user
      @custom_search_engine = CustomSearchEngine.find(params[:id])
      correct_user!(@custom_search_engine.author)
    end

    def only_publish_cse_available
      @custom_search_engine = CustomSearchEngine.find(params[:id])
      if @custom_search_engine.status == 'draft' && current_user != @custom_search_engine.author
        flash[:error] = I18n.t('human.errors.only_publish_cse_available')
        redirect_to nodes_path
      end
    end
end
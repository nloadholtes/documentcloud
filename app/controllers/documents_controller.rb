class DocumentsController < ApplicationController
  layout nil

  before_filter(:bouncer, :only => [:show]) unless Rails.env.development?

  SIZE_EXTRACTOR        = /-(\w+)\Z/
  PAGE_NUMBER_EXTRACTOR = /-p(\d+)/

  def show
    current_document(true)
    respond_to do |format|
      format.pdf  { redirect_to(current_document.pdf_url) }
      format.text { redirect_to(current_document.full_text_url) }
      format.html do
        return if date_requested?
        return if entity_requested?
        @edits_enabled = true
      end
      format.json do
        @response = current_document.canonical
        return if jsonp_request?
        render :json => @response
      end
    end
  end

  def update
    current_document(true)
    json = JSON.parse(params[:json]).symbolize_keys
    access = json[:access] && json[:access].to_i
    current_document.set_access(access) if access && current_document.access != access
    current_document.update_attributes(:description => json[:description].mb_chars[0...255]) if json[:description]
    current_document.update_attributes(:remote_url => json[:remote_url]) if json[:remote_url]
    json current_document
  end

  def destroy
    current_document(true).destroy
    json nil
  end

  # TODO: Access-control this:
  def metadata
    meta = Metadatum.all(:conditions => ["document_id in (#{params[:ids].join(',')}) and not kind = ?", 'category'])
    json 'metadata' => meta
  end

  # TODO: Access-control this:
  def dates
    dates = MetadataDate.all(:conditions => {:document_id => params[:ids]})
    json 'dates' => dates
  end

  def send_pdf
    redirect_to(current_document(true).pdf_url(:direct))
  end

  def send_page_image
    return not_found unless current_page
    size = params[:page_name][SIZE_EXTRACTOR, 1]
    redirect_to(current_page.authorized_image_url(size))
  end

  def send_full_text
    send_data(current_document(true).text, :disposition => 'inline', :type => :txt)
  end

  def send_page_text
    return not_found unless current_page
    @response = current_page.text
    return if jsonp_request?
    render :text => @response
  end

  def set_page_text
    return not_found unless current_page
    return forbidden unless current_account.owns_or_administers?(current_page)
    json current_page.update_attributes(pick(params, :text))
  end

  def search
    doc          = current_document(true)
    page_numbers = doc.pages.search_text(params[:q]).map(&:page_number)
    @response    = {'query' => params[:q], 'results' => page_numbers}
    return if jsonp_request?
    render :json => @response
  end


  private

  def date_requested?
    return false unless params[:date]
    date = Time.at(params[:date].to_i).to_date
    meta = current_document.metadata_dates.first(:conditions => {:date => date})
    redirect_to current_document.document_viewer_url(:date => meta)
  end

  def entity_requested?
    return false unless params[:entity]
    meta = current_document.metadata.find(params[:entity])
    redirect_to current_document.document_viewer_url(:entity => meta)
  end

  def current_document(exists=false)
    @current_document ||= exists ?
      Document.accessible(current_account, current_organization).find(params[:id]) :
      Document.new(:id => params[:id])
  end

  def current_page
    num = params[:page_name][PAGE_NUMBER_EXTRACTOR, 1]
    return bad_request unless num
    @current_page ||= current_document(true).pages.find_by_page_number(num.to_i)
  end

end
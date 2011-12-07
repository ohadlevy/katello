#
# Copyright 2011 Red Hat, Inc.
#
# This software is licensed to you under the GNU General Public
# License as published by the Free Software Foundation; either version
# 2 of the License (GPLv2) or (at your option) any later version.
# There is NO WARRANTY for this software, express or implied,
# including the implied warranties of MERCHANTABILITY,
# NON-INFRINGEMENT, or FITNESS FOR A PARTICULAR PURPOSE. You should
# have received a copy of GPLv2 along with this software; if not, see
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.txt.

require 'resources/pulp' if AppConfig.katello?

class Api::PackagesController < Api::ApiController

  respond_to :json

  # TODO: define authorization rules
  skip_before_filter :authorize

  def index
    packages = Repository.find(params[:repository_id]).packages
    render :json => packages
  end

  def show
    package = Pulp::Package.find(params[:id])
    render :json => package
  end

end
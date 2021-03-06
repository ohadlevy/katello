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


class ChangesetErratumValidator < ActiveModel::Validator
  def validate(record)
    from_env = record.changeset.environment.prior
    to_env   = record.changeset.environment
    product = Product.find(record.product_id)

    record.errors[:base] << _("Erratum '%s' doesn't belong to the specified product!") % record.errata_id and return if record.repositories.empty?
    record.errors[:base] << _("Repository of the erratum '%s' has not been promoted into the target environment!") % record.errata_id and return if record.promotable_repositories.empty?

    unfiltered_repositories = record.promotable_repositories.delete_if {|repo| record.blocked_by_filters?((repo.filters + repo.product.filters).uniq)}
    record.errors[:base] << _("Filters assigned to repository or product of erratum '%s' block it from promotion!") % record.errata_id and return if unfiltered_repositories.empty?
  end
end

class ChangesetErratum < ActiveRecord::Base
  include Authorization

  belongs_to :changeset, :inverse_of=>:errata
  belongs_to :product
  validates :display_name, :length => { :maximum => 255 }
  validates_with ChangesetErratumValidator

  def repositories
    return @repos if not @repos.nil?

    from_env = self.changeset.environment.prior
    @repos = []

    self.product.repos(from_env).each do |repo|
      @repos << repo if repo.has_erratum? self.errata_id
    end
    @repos
  end

  def promotable_repositories
    to_env = self.changeset.environment

    repos = []
    self.repositories.each do |repo|
      repos << repo if repo.is_cloned_in? to_env
    end
    repos
  end

  def blocked_by_filters? filters
    package_filters = filters.map{|f| f.package_list}.flatten(1).uniq
    package_filters.each do |filter|
        re = Regexp.new(filter)
        if erratum_pacakges.any? {|pack| re =~ pack["filename"] }
            return true
        end
    end
    return false
  end

  # returns list of virtual permission tags for the current user
  def self.list_tags
    select('id,display_name').all.collect { |m| VirtualTag.new(m.id, m.display_name) }
  end

  private
  def erratum_pacakges
    Glue::Pulp::Errata::find(self.errata_id).pkglist.map{|list| list["packages"]}.flatten(1).uniq
  end

end

class AutoWatchFilter < ActiveRecord::Base
  serialize :filters
  belongs_to :project
  belongs_to :group

  validates_presence_of :name, :on => :save
  validates_presence_of :group_id, :on => :save
  validates_presence_of :project_id, :on => :save


  def initialize(attributes = nil)
    super attributes
    self.filters ||= { 'status_id' => {:operator => "o", :values => [""]} }
  end

  def available_filters
    return @available_filters if @available_filters

    trackers = project.nil? ? Tracker.find(:all, :order => 'position') : project.rolled_up_trackers

    @available_filters = { "status_id" => { :type => :list_status, :order => 1, :values => IssueStatus.find(:all, :order => 'position').collect{|s| [s.name, s.id.to_s] } , :name => l(:field_status) },
                           "tracker_id" => { :type => :list, :order => 2, :values => trackers.collect{|s| [s.name, s.id.to_s] }, :name => l(:field_tracker)  },
                           "priority_id" => { :type => :list, :order => 3, :values => IssuePriority.all.collect{|s| [s.name, s.id.to_s] }, :name => l(:field_priority)  },
                           "subject" => { :type => :text, :order => 8, :name => l(:field_subject)  },
                           "created_on" => { :type => :date_past, :order => 9, :name => l(:field_created_on)  },
                           "updated_on" => { :type => :date_past, :order => 10, :name => l(:field_updated_on)  },
                           "start_date" => { :type => :date, :order => 11, :name => l(:field_start_date)  },
                           "due_date" => { :type => :date, :order => 12, :name => l(:field_due_date) },
                           "estimated_hours" => { :type => :integer, :order => 13, :name => l(:field_estimated_hours) },
                           "done_ratio" =>  { :type => :integer, :order => 14, :name => l(:field_done_ratio) }}


    user_values = []
    user_values << ["<< #{l(:label_me)} >>", "me"] if User.current.logged?
    user_values += project.users.sort.collect{|s| [s.name, s.id.to_s] }

    @available_filters["assigned_to_id"] = { :type => :list_optional, :order => 4, :values => user_values, :name => l(:field_assigned_to) } unless user_values.empty?
    @available_filters["author_id"] = { :type => :list, :order => 5, :values => user_values, :name => l(:field_author) } unless user_values.empty?

    group_values = Group.all.collect {|g| [g.name, g.id.to_s] }
    @available_filters["member_of_group"] = { :type => :list_optional, :order => 6, :values => group_values, :name => l(:field_member_of_group) } unless group_values.empty?

    role_values = Role.givable.collect {|r| [r.name, r.id.to_s] }
    @available_filters["assigned_to_role"] = { :type => :list_optional, :order => 7, :values => role_values, :name => l(:field_assigned_to_role) } unless role_values.empty?
    @available_filters["watcher_id"] = { :type => :list, :order => 15, :values => [["<< #{l(:label_me)} >>", "me"]], :name => l(:field_watcher) }

    categories = project.issue_categories.all
    unless categories.empty?
      @available_filters["category_id"] = { :type => :list_optional, :order => 6, :values => categories.collect{|s| [s.name, s.id.to_s] }, :name => l(:field_category)  }
    end
    versions = project.shared_versions.all
    unless versions.empty?
      @available_filters["fixed_version_id"] = { :type => :list_optional, :order => 7, :values => versions.sort.collect{|s| ["#{s.project.name} - #{s.name}", s.id.to_s] }, :name => l(:field_fixed_version) }
    end
    unless project.leaf?
      subprojects = project.descendants.visible.all
      unless subprojects.empty?
        @available_filters["subproject_id"] = { :type => :list_subprojects, :order => 13, :values => subprojects.collect{|s| [s.name, s.id.to_s] } }
      end
    end
    add_custom_fields_filters(project.all_issue_custom_fields)
    project_hierarchy = []
    project.hierarchy.each { |x| project_hierarchy << x }
    contexts = []
    project_hierarchy.each { |x| contexts << TaggingPlugin::ContextHelper.context_for(x) }
    tags = []
    contexts.each do |context|
      tags += ActsAsTaggableOn::Tag.find(:all, :conditions => ["id in (select tag_id from taggings where taggable_type = 'Issue' and context = ?)", context])
    end
    tags = tags.collect {|tag| [tag.name.gsub(/^#/, ''), tag.name]}
    @available_filters["tags"] = {
        :type => :list_optional,
        :values => tags.uniq.sort,
        :name => l(:field_tags),
        :order => 21,
        :field => "tags"
    }

    @available_filters
  end


  def available_filters_as_json
    json = {}
    available_filters.each do |field, options|
      json[field] = options.slice(:type, :name, :values).stringify_keys
    end
    json
  end


  def add_custom_fields_filters(custom_fields)
    @available_filters ||= {}

    custom_fields.select(&:is_filter?).each do |field|
      case field.field_format
      when "text"
        options = { :type => :text, :order => 20 }
      when "list"
        options = { :type => :list_optional, :values => field.possible_values, :order => 20}
      when "date"
        options = { :type => :date, :order => 20 }
      when "bool"
        options = { :type => :list, :values => [[l(:general_text_yes), "1"], [l(:general_text_no), "0"]], :order => 20 }
      when "user", "version"
        next unless project
        options = { :type => :list_optional, :values => field.possible_values_options(project), :order => 20}
      else
        options = { :type => :string, :order => 20 }
      end
      @available_filters["cf_#{field.id}"] = options.merge({ :name => field.name })
    end
  end

  def has_filter?(field)
    filters and filters[field]
  end
  def operator_for(field)
    has_filter?(field) ? filters[field][:operator] : nil
  end

  def values_for(field)
    has_filter?(field) ? filters[field][:values] : nil
  end

  def value_for(field, index=0)
    (values_for(field) || [])[index]
  end

  def label_for(field)
    label = available_filters[field][:name] if available_filters.has_key?(field)
    label ||= field.gsub(/\_id$/, "")
  end
  
  def add_filter(field, operator, values)
    # values must be an array
    return unless values and values.is_a? Array # and !values.first.empty?
    # check if field is defined as an available filter
    if available_filters.has_key? field
      filter_options = available_filters[field]
      # check if operator is allowed for that filter
      #if @@operators_by_filter_type[filter_options[:type]].include? operator
      #  allowed_values = values & ([""] + (filter_options[:values] || []).collect {|val| val[1]})
      #  filters[field] = {:operator => operator, :values => allowed_values } if (allowed_values.first and !allowed_values.first.empty?) or ["o", "c", "!*", "*", "t"].include? operator
      #end
      filters[field] = {:operator => operator, :values => values }
    end
  end

  def add_short_filter(field, expression)
    return unless expression
    parms = expression.scan(/^(o|c|!\*|!|\*)?(.*)$/).first
    add_filter field, (parms[0] || "="), [parms[1] || ""]
  end

  # Add multiple filters using +add_filter+
  def add_filters(fields, operators, values)
    if fields.is_a?(Array) && operators.is_a?(Hash) && values.is_a?(Hash)
      fields.each do |field|
        add_filter(field, operators[field], values[field])
      end
    end
  end

  def issues(options={})
    Issue.find :all, :include => ([:status, :project] + (options[:include] || [])).uniq,
                     :conditions => statement,
                     :limit  => options[:limit],
                     :offset => options[:offset]
  rescue ::ActiveRecord::StatementInvalid => e
    raise StatementInvalid.new(e.message)
  end

 def sql_for_field(field, operator, value, db_table, db_field, is_custom_filter=false)
    if field == "tags"
      selected_values = values_for(field)
      selected_values.each do |tag|
        tag_find = Tag.where(:name => tag).last
        tag_find.last_update = Date.current
        tag_find.save
      end
      if operator == '!*'
        sql = "(#{Issue.table_name}.id NOT IN (select taggable_id from taggings where taggable_type='Issue'))"
        return sql
      elsif operator == "*"
        sql = "(#{Issue.table_name}.id IN (select taggable_id from taggings where taggable_type='Issue'))"
        return sql
      else
        sql = selected_values.collect{|val| "'#{ActiveRecord::Base.connection.quote_string(val.gsub('\'', ''))}'"}.join(',')
        sql = "(#{Issue.table_name}.id in (select taggable_id from taggings join tags on tags.id = taggings.tag_id where taggable_type='Issue' and tags.name in (#{sql})))"
        sql = "(not #{sql})" if operator == '!'
        return sql
      end
    end
    sql = ''
    case operator
    when "="
      if value.any?
        sql = "#{db_table}.#{db_field} IN (" + value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",") + ")"
      else
        # IN an empty set
        sql = "1=0"
      end
    when "!"
      if value.any?
        sql = "(#{db_table}.#{db_field} IS NULL OR #{db_table}.#{db_field} NOT IN (" + value.collect{|val| "'#{connection.quote_string(val)}'"}.join(",") + "))"
      else
        # NOT IN an empty set
        sql = "1=1"
      end
    when "!*"
      sql = "#{db_table}.#{db_field} IS NULL"
      sql << " OR #{db_table}.#{db_field} = ''" if is_custom_filter
    when "*"
      sql = "#{db_table}.#{db_field} IS NOT NULL"
      sql << " AND #{db_table}.#{db_field} <> ''" if is_custom_filter
    when ">="
      sql = "#{db_table}.#{db_field} >= #{value.first.to_i}"
    when "<="
      sql = "#{db_table}.#{db_field} <= #{value.first.to_i}"
    when "o"
      sql = "#{IssueStatus.table_name}.is_closed=#{connection.quoted_false}" if field == "status_id"
    when "c"
      sql = "#{IssueStatus.table_name}.is_closed=#{connection.quoted_true}" if field == "status_id"
    when ">t-"
      sql = date_range_clause(db_table, db_field, - value.first.to_i, 0)
    when "<t-"
      sql = date_range_clause(db_table, db_field, nil, - value.first.to_i)
    when "t-"
      sql = date_range_clause(db_table, db_field, - value.first.to_i, - value.first.to_i)
    when ">t+"
      sql = date_range_clause(db_table, db_field, value.first.to_i, nil)
    when "<t+"
      sql = date_range_clause(db_table, db_field, 0, value.first.to_i)
    when "t+"
      sql = date_range_clause(db_table, db_field, value.first.to_i, value.first.to_i)
    when "t"
      sql = date_range_clause(db_table, db_field, 0, 0)
    when "w"
      first_day_of_week = l(:general_first_day_of_week).to_i
      day_of_week = Date.today.cwday
      days_ago = (day_of_week >= first_day_of_week ? day_of_week - first_day_of_week : day_of_week + 7 - first_day_of_week)
      sql = date_range_clause(db_table, db_field, - days_ago, - days_ago + 6)
    when "~"
      sql = "LOWER(#{db_table}.#{db_field}) LIKE '%#{connection.quote_string(value.first.to_s.downcase)}%'"
    when "!~"
      sql = "LOWER(#{db_table}.#{db_field}) NOT LIKE '%#{connection.quote_string(value.first.to_s.downcase)}%'"
    end

    return sql
  end

  def project_statement
    project_clauses = []
    if project && !project.descendants.active.empty?
      ids = [project.id]
      if has_filter?("subproject_id")
        case operator_for("subproject_id")
        when '='
          # include the selected subprojects
          ids += values_for("subproject_id").each(&:to_i)
        when '!*'
          # main project only
        else
          # all subprojects
          ids += project.descendants.collect(&:id)
        end
      elsif Setting.display_subprojects_issues?
        ids += project.descendants.collect(&:id)
      end
      project_clauses << "#{Project.table_name}.id IN (%s)" % ids.join(',')
    elsif project
      project_clauses << "#{Project.table_name}.id = %d" % project.id
    end
    project_clauses.any? ? project_clauses.join(' AND ') : nil
  end

  def statement
    # filters clauses
    filters_clauses = []
    filters.each_key do |field|
      next if field == "subproject_id"
      v = values_for(field).clone
      next unless v and !v.empty?
      operator = operator_for(field)

      # "me" value subsitution
      if %w(assigned_to_id author_id watcher_id).include?(field)
        v.push(User.current.logged? ? User.current.id.to_s : "0") if v.delete("me")
      end

      sql = ''
      if field =~ /^cf_(\d+)$/
        # custom field
        db_table = CustomValue.table_name
        db_field = 'value'
        is_custom_filter = true
        sql << "#{Issue.table_name}.id IN (SELECT #{Issue.table_name}.id FROM #{Issue.table_name} LEFT OUTER JOIN #{db_table} ON #{db_table}.customized_type='Issue' AND #{db_table}.customized_id=#{Issue.table_name}.id AND #{db_table}.custom_field_id=#{$1} WHERE "
        sql << sql_for_field(field, operator, v, db_table, db_field, true) + ')'
      elsif field == 'watcher_id'
        db_table = Watcher.table_name
        db_field = 'user_id'
        sql << "#{Issue.table_name}.id #{ operator == '=' ? 'IN' : 'NOT IN' } (SELECT #{db_table}.watchable_id FROM #{db_table} WHERE #{db_table}.watchable_type='Issue' AND "
        sql << sql_for_field(field, '=', v, db_table, db_field) + ')'
      elsif field == "member_of_group" # named field
        if operator == '*' # Any group
          groups = Group.all
          operator = '=' # Override the operator since we want to find by assigned_to
        elsif operator == "!*"
          groups = Group.all
          operator = '!' # Override the operator since we want to find by assigned_to
        else
          groups = Group.find_all_by_id(v)
        end
        groups ||= []

        members_of_groups = groups.inject([]) {|user_ids, group|
          if group && group.user_ids.present?
            user_ids << group.user_ids
          end
          user_ids.flatten.uniq.compact
        }.sort.collect(&:to_s)

        sql << '(' + sql_for_field("assigned_to_id", operator, members_of_groups, Issue.table_name, "assigned_to_id", false) + ')'

      elsif field == "assigned_to_role" # named field
        if operator == "*" # Any Role
          roles = Role.givable
          operator = '=' # Override the operator since we want to find by assigned_to
        elsif operator == "!*" # No role
          roles = Role.givable
          operator = '!' # Override the operator since we want to find by assigned_to
        else
          roles = Role.givable.find_all_by_id(v)
        end
        roles ||= []

        members_of_roles = roles.inject([]) {|user_ids, role|
          if role && role.members
            user_ids << role.members.collect(&:user_id)
          end
          user_ids.flatten.uniq.compact
        }.sort.collect(&:to_s)

        sql << '(' + sql_for_field("assigned_to_id", operator, members_of_roles, Issue.table_name, "assigned_to_id", false) + ')'
      else
        # regular field
        db_table = Issue.table_name
        db_field = field
        sql << '(' + sql_for_field(field, operator, v, db_table, db_field) + ')'
      end
      filters_clauses << sql

    end if filters and valid?

    filters_clauses << project_statement
    filters_clauses.reject!(&:blank?)

    filters_clauses.any? ? filters_clauses.join(' AND ') : nil
  end


  def all_projects
    @all_projects ||= Project.visible.all
  end


  def all_projects_values
    return @all_projects_values if @all_projects_values

    values = []
    Project.project_tree(all_projects) do |p, level|
      prefix = (level > 0 ? ('--' * level + ' ') : '')
      values << ["#{prefix}#{p.name}", p.id.to_s]
    end
    @all_projects_values = values
  end

end

#class CwaAs < ActiveRecord::Base
class CwaAccountsignup
  # This gets us all of our accessor methods for plugin settings
  # and ipa-based attributes
  @@ipa_result = Hash.new
  @@fields = Hash.new

  def method_missing(name, *args, &blk)
    # If its an option in the settings hash, return it
    Rails.logger.debug "mm() called with " + name.to_s
    if args.empty? && blk.nil?
      make_user_fields
      if @@fields != nil && @@fields[User.current.login].has_key?(name)
        return @@fields[User.current.login][name.to_sym]
      end

      ipa_query
      if @@ipa_result.has_key?(User.current.login) &&
        @@ipa_result[User.current.login].try(:[], :result) &&
        @@ipa_result[User.current.login][:result].try(:[], name.to_s)
        return @@ipa_result[User.current.login][:result][name.to_s].first
      end
      super
    else
      super
    end
  end

  # List of allowed shells
  def shells
     { "/bin/sh" => 0, "/bin/bash" => 1, "/bin/ash" => 2, "/bin/zsh" => 3,  "/bin/csh" => 4, "/bin/tcsh" => 5 }
  end

  # Set user shell
  def set_loginshell(shell)
    user_set :loginshell => shell
  end

  # Force a full query on the next ipa_query run
  def ipa_query_cache_reset
    if @@ipa_result.has_key?(User.current.login) && @@ipa_result[User.current.login].has_key?(:timestamp)
      @@ipa_result[User.current.login][:timestamp] -= 60.seconds
    end
  end

  # Get wonderful attributes from IPA server
  def ipa_query
    if @@ipa_result[User.current.login].try(:[], :timestamp) && (Time.now - @@ipa_result[User.current.login][:timestamp]) <= 30.seconds
      return
    end
      
    Rails.logger.debug "ipa_query() => " + @@ipa_result[User.current.login].to_s
    json_string = <<EOF
{ "method": "user_show", 
  "params":[
   [],
   { "uid":"#{User.current.login}" }
   ] 
}
EOF
    r = Redmine::Cwa.simple_json_rpc(
      "https://" + Redmine::Cwa.ipa_server + "/ipa/json", 
      Redmine::Cwa.ipa_account,
      Redmine::Cwa.ipa_password,
      json_string
    )
    Rails.logger.debug "ipa_query() => " + r['result'].to_s
    if r != nil && r['result'] != nil 
      @@ipa_result = { User.current.login => { :timestamp => Time.now, :result => r['result']['result'] } }
    else
      @@ipa_result = { User.current.login => nil }
    end
  end
      
  # update user parameters in IPA
  def user_set(params)
    json_string = <<EOF
{ "method": "user_mod", 
  "params":[
   [],
    { 
     "uid":"#{User.current.login}",
EOF

    p_keys = params.keys
    last = p_keys.pop
    params.keys.each do |k|
      json_string += "     \"#{k.to_s}\":\"#{params[k]}\",\n" 
    end

    json_string += <<EOF 
     "#{last.to_s}":"#{params[last]}"
    }
   ] 
}
EOF
    Redmine::Cwa.simple_json_rpc(
      "https://" + Redmine::Cwa.ipa_server + "/ipa/json", 
      Redmine::Cwa.ipa_account,
      Redmine::Cwa.ipa_password,
      json_string
    )
    self.ipa_query_cache_reset
    ipa_query
  end

  # Populate custom_fields as accessible attributes
  def make_user_fields
    @@fields[User.current.login] = Hash.new
    User.current.available_custom_fields.each do |field|
      @@fields[User.current.login][field.name.to_sym] = User.current.custom_field_value(field.id)
    end
    @@fields
  end
end

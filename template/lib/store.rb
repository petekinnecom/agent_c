# frozen_string_literal: true

class Store < VersionedStore::Base
  include AgentC::Store

  record(:summary) do
    schema do |t|
      # we'll input this data
      t.string(:language)

      # claude will generate this data
      t.string(:input_path)
      t.string(:summary_body)
      t.string(:summary_path)
    end
  end
end

# frozen_string_literal: true

require "pathname"

module AgentC
  module Tools
    module Paths
      module_function

      def relative_to_dir(dir, path)
        if path.start_with?(dir)
          path
        else
          File.join(dir, path)
        end
      end

      def allowed?(dir, path)
        child?(dir, path)
      end

      def child?(parent_dir, child_path)

        unless child_path.start_with?("/")
          child_path = File.join(parent_dir, child_path)
        end

        child = Pathname.new(child_path).expand_path
        parent = Pathname.new(parent_dir).expand_path

        relative = child.relative_path_from(parent)
        !relative.to_s.start_with?('..')
      end
    end
  end
end

module ConsoleAgent
  module Channel
    class Base
      def display(text);            raise NotImplementedError; end
      def display_dim(text);        raise NotImplementedError; end
      def display_warning(text);    raise NotImplementedError; end
      def display_error(text);      raise NotImplementedError; end
      def display_code(code);       raise NotImplementedError; end
      def display_result(text);     raise NotImplementedError; end
      def prompt(text);             raise NotImplementedError; end
      def confirm(text);            raise NotImplementedError; end
      def user_identity;            raise NotImplementedError; end
      def mode;                     raise NotImplementedError; end
      def supports_editing?;        false; end
      def edit_code(code);          code; end
      def wrap_llm_call(&block);    yield; end
    end
  end
end

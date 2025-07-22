require "json"
require "../../tools"
require "../../ext/enum"
require "../../base/*"
require "../notification_message"

module LSP
  # The document will save notification is sent from the client to the server before the document is actually saved.
  class WillSaveNotification < NotificationMessage
    @method = "textDocument/willSave"
    property params : WillSaveTextDocumentParams
  end

  struct WillSaveTextDocumentParams
    include Initializer
    include JSON::Serializable

    # The document that will be saved.
    @[JSON::Field(key: "textDocument")]
    property text_document : TextDocumentIdentifier

    # The 'TextDocumentSaveReason'.
    property reason : TextDocumentSaveReason
  end

  # Represents reasons why a text document is saved.
  Enum.number TextDocumentSaveReason do
    # Manually triggered, e.g. by the user pressing save, by starting debugging,
    # or by an API call.
    Manual = 1
    # Automatic after a delay.
    AfterDelay = 2
    # When the editor lost focus.
    FocusOut = 3
  end
end

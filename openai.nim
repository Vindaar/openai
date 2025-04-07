import std / [httpclient, json, strformat, strutils, times]
import shell


const
  apiUrl = "https://api.openai.com/v1/"

type
  OpenAIClientObj* = object
    client*: HttpClient
    apiKey: string
    projectId: string
  OpenAIClient* = ref OpenAIClientObj

type
  Message* = object
    role*: string
    content*: string

  Choice* = object
    index*: int
    message*: Message
    logprobs*: JsonNode
    finish_reason*: string

  Usage* = object
    prompt_tokens*: int
    completion_tokens*: int
    total_tokens*: int

  OpenAIResponse* = object
    id*: string
    `object`*: string
    created*: int
    model*: string
    choices*: seq[Choice]
    usage*: Usage
    system_fingerprint*: string

  ## TODO: Could have an enum for the `role` field
  Content* = object
    role*: string
    content*: string


proc `=destroy`*(o: OpenAIClientObj) =
  o.client.close()
  `=destroy`(o.client)
  `=destroy`(o.apiKey)

proc newOpenAIClient*(apiKey, projectId: string): OpenAIClient =
  ## Creates a new OpenAIClient instance.
  result = OpenAIClient(apiKey: apiKey,
                        projectId: projectId,
                        client: newHttpClient())

proc createHeaders(apiKey, projectId: string): HttpHeaders =
  ## Creates the headers required for the API request.
  result = newHttpHeaders()
  result.add("Content-Type", "application/json")
  result.add("Authorization", "Bearer " & apiKey)
  #result.add("OpenAI-Project", $projectId)

proc sendRequest(cl: OpenAIClient, endpoint: string, body: JsonNode): JsonNode =
  ## Sends a POST request to the given endpoint with the provided body.
  let fullUrl = fmt"{apiUrl}/{endpoint}"
  let headers = createHeaders(cl.apiKey, cl.projectId)
  let response = cl.client.request(fullUrl, HttpPost, $body, headers)

  if response.status != $Http200:
    raise newException(ValueError, "Error: " & response.status)

  return parseJson(response.body)

proc completion*(client: OpenAIClient, systemPrompt, prompt: string,
                 contents: seq[Content], model: string = "gpt-4o-mini",
                 maxTokens: int = 8192, temperature = 0.0): JsonNode =
  ## Sends a completion request to the OpenAI API.
  let sys = %*{
    "role" : "system",
    "content" : systemPrompt
    }

  var msgs = % [sys]
  for el in contents:
    msgs.add %el
  msgs.add %*{
    "role" : "user",
    "content" : prompt
  }

  let body = %*{
    "model": model,
    "messages" : msgs,
    "max_tokens": maxTokens,
    "temperature" : temperature
  }

  result = client.sendRequest("chat/completions", body)

proc completion*(client: OpenAIClient, systemPrompt, prompt: string,
                 model: string = "gpt-4o-mini", maxTokens: int = 8192,
                 temperature = 0.0): JsonNode =
  ## Sends a completion request to the OpenAI API.
  result = client.completion(systemPrompt, prompt, @[], model, maxTokens, temperature)

proc decryptFile*(filePath: string): string =
  ## Decrypts the GPG file and returns the content as a string.
  let gpgCommand = "gpg --quiet --batch --yes --decrypt " & filePath
  const config: set[DebugOutputKind] = {}
  let (res, err) = shellVerbose(debug = config):
    ($gpgCommand)
  result = res

proc extractAPIKey*(content: string): string =
  ## Parses the decrypted content to extract the API key.
  let lines = content.splitLines()
  for line in lines:
    if line.startsWith("machine api.openai.com login api_key password"):
      return line.split(" ")[^1]
  raise newException(ValueError, "API key not found in authinfo.gpg")

when isMainModule:
  # Usage example:
  let decryptedContent = decryptFile("/home/foobar/.authinfo.gpg")
  let apiKey = extractAPIKey(decryptedContent)
  echo "API Key: ", apiKey

  # Now you can use the apiKey with the OpenAIClient.

  # Usage example:
  let client = newOpenAIClient(apiKey, "MainAPIKey")
  let response = client.completion("You are a helpful assistant.", "Hello, how are you?")
  echo response

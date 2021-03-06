_                = require 'lodash'
http             = require 'http'
uuid             = require 'uuid'
DeviceManager    = require 'meshblu-core-manager-device'
mongoStatusCodes = require './mongo-update-codes.json'

class UpdateDevice
  constructor: ({datastore,uuidAliasResolver,@jobManager}) ->
    @deviceManager = new DeviceManager {datastore, uuidAliasResolver}

  do: (request, callback) =>
    { toUuid, auth } = request.metadata
    if auth?
      updatedBy = auth.as ? auth.uuid

    try
      update = JSON.parse request.rawData
    catch error
      return @_doUserErrorCallback request, new Error("Error parsing JSON: #{error.message}"), 422, callback

    @deviceManager.update {uuid: toUuid, updatedBy, data: update}, (error, result) =>
      return @_doUserErrorCallback request, error, 422, callback if @_isUserError error
      return @_doErrorCallback request, error, callback if error?

      @deviceManager.findOne {uuid: toUuid}, (error, message) =>
        return @_doErrorCallback request, error, callback if error?
        return @_doCallback request, 404, callback unless message?
        return @_doCallback request, 304, callback unless result.updated

        newAuth =
          uuid: toUuid
        configureMessageOptions =
          messageType: 'config'
          jobType: 'DeliverConfigMessage'
          toUuid: toUuid
          fromUuid: toUuid
          message: message
          auth: newAuth
        configureSentOptions =
          messageType: 'config'
          jobType: 'DeliverConfigureSent'
          fromUuid: toUuid
          message: message
          auth: newAuth
        @_createJob configureMessageOptions, (error) =>
          @_createJob configureSentOptions, (error) =>
            return @_doErrorCallback request, error, callback if error?
            return @_doCallback request, 204, callback

  _createJob: ({messageType, jobType, toUuid, message, fromUuid, auth}, callback) =>
    request =
      data: message
      metadata:
        auth: auth
        toUuid: toUuid
        fromUuid: fromUuid
        jobType: jobType
        messageType: messageType
        responseId: uuid.v4()

    @jobManager.createRequest 'request', request, callback

  _doCallback: (request, code, callback) =>
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
    callback null, response

  _doErrorCallback: (request, error, callback) =>
    code = error.code ? 500
    code = 500 unless http.STATUS_CODES[code]?
    response =
      metadata:
        responseId: request.metadata.responseId
        code: code
        status: http.STATUS_CODES[code]
        error:
          message: error.message
    callback null, response

  _doUserErrorCallback: (request, error, code, callback) =>
    error.code = code
    @_doErrorCallback request, error, callback

  _isUserError: (error) =>
    return false unless error?
    _.include mongoStatusCodes, error.code

module.exports = UpdateDevice

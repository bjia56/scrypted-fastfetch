import { Terminal } from '@xterm/xterm'
import { FitAddon } from '@xterm/addon-fit'
import { ImageAddon } from '@xterm/addon-image'
import xtermCSS from '@xterm/xterm/css/xterm.css?raw'

import { createAsyncQueue } from "@scrypted/common/src/async-queue";
import { connectScryptedClient, getCurrentBaseUrl } from "@scrypted/client";

import path from 'path';

createAsyncQueueFromGenerator = (generator) ->
    queue = createAsyncQueue()

    do ->
        (() ->
            try
                for await item from generator
                    await queue.enqueue item
            catch error
                queue.end error
            queue.end()
        )()

    return queue

class XFastfetchElement extends HTMLElement
    constructor: ->
        super()
        @terminal = null
        @fitAddon = null
        @imageAddon = null
        @terminalContainer = null
        @resizeObserver = null
        @controlQueue = null
        @dataQueue = null
        @disposed = false
        @inputDisabled = false
        @attachShadow mode: 'open'

    connectedCallback: ->
        @render()
        @initializeTerminal()
        @connectStream()

    disconnectedCallback: ->
        @cleanup()

    render: ->
        return unless @shadowRoot

        # Create container for terminal
        @terminalContainer = document.createElement 'div'
        @terminalContainer.style.width = 'calc(100% - 24px)'
        @terminalContainer.style.height = '100%'
        @terminalContainer.style.overflow = 'hidden'
        @terminalContainer.style.marginLeft = '12px'
        @terminalContainer.style.marginRight = '12px'

        # Inject xterm CSS into shadow DOM
        xtermStyle = document.createElement 'style'
        xtermStyle.textContent = xtermCSS

        @shadowRoot.appendChild xtermStyle
        @shadowRoot.appendChild @terminalContainer

    initializeTerminal: ->
        return unless @terminalContainer

        # Create terminal instance
        @terminal = new Terminal
            convertEol: true
            fontSize: 12

        # Initialize addons
        @fitAddon = new FitAddon()
        @imageAddon = new ImageAddon()

        # Load addons
        @terminal.loadAddon @fitAddon
        @terminal.loadAddon @imageAddon

        # Open terminal in container
        @terminal.open @terminalContainer

        # Fit terminal to container
        @fitAddon.fit()

        # Set up resize observer to handle container size changes
        @resizeObserver = new ResizeObserver =>
            @fitAddon?.fit()
        @resizeObserver.observe @terminalContainer

        @dataQueue = createAsyncQueue()
        @controlQueue = createAsyncQueue()

        #@dataQueue.enqueue undefined
        @controlQueue.enqueue
            interactive: true
        @controlQueue.enqueue
            dim:
                cols: @terminal.cols
                rows: @terminal.rows

        # Set up terminal input handlers
        @terminal.onData (data) =>
            return if @disposed
            @dataQueue.enqueue (Buffer.from data, 'utf-8')

        @terminal.onBinary (data) =>
            return if @disposed
            @dataQueue.enqueue (Buffer.from data, 'binary')

        @terminal.onResize (dim) =>
            return if @disposed
            @controlQueue.enqueue
                dim: dim
            @dataQueue.enqueue (Buffer.alloc 0)

    createLocalGenerator: ->
        loop
            # First yield control messages
            ctrlBuffers = @controlQueue.clear()
            if ctrlBuffers.length > 0
                for buf in ctrlBuffers
                    yield JSON.stringify buf
                continue

            # Then yield data buffers
            dataBuffers = @dataQueue.clear()
            if dataBuffers.length == 0
                buf = await @dataQueue.dequeue()
                if buf.length > 0
                    yield buf
                continue

            concat = Buffer.concat dataBuffers
            if concat.length > 0
                yield concat

    connectStream: ->
        return if @streamReader

        try
            pluginId = '@bjia56/scrypted-fastfetch'
            url = new URL window.location.href
            deviceId = path.basename (url.hash.slice 1)

            # Connect to the plugin
            pluginClient = await connectScryptedClient
                baseUrl: getCurrentBaseUrl()
                pluginId: '@scrypted/core'

            systemManager = pluginClient.systemManager
            connectRPCObject = pluginClient.connectRPCObject

            # Get the stream service device
            plugin = systemManager.getDeviceByName pluginId
            device = systemManager.getDeviceById deviceId
            streamDevice = await plugin.getDevice device.nativeId
            streamDevice = await connectRPCObject streamDevice

            unless streamDevice
                throw new Error "Stream device not found: #{nativeId}"

            # Create local generator for sending data
            localStream = createAsyncQueueFromGenerator @createLocalGenerator()

            # Connect to remote stream
            remoteStream = await streamDevice.connectStream localStream.queue, { pluginId }

            # Read from remote stream
            for await message from remoteStream
                break unless message
                @terminal.write (new Uint8Array message)

        catch error
            console.error 'Failed to connect stream:', error
            @terminal.write "\r\n\x1B[1;31mStream connection failed: #{error.message}\x1B[0m\r\n"

    cleanup: ->
        @disposed = true

        # Clean up queues
        @controlQueue?.clear()
        @dataQueue?.clear()
        @controlQueue = null
        @dataQueue = null

        # Clean up stream reader
        @streamReader = null

        # Clean up observers and terminal
        @resizeObserver?.disconnect()
        @terminal?.dispose()
        @terminal = null
        @fitAddon = null
        @imageAddon = null
        @terminalContainer = null
        @scryptedClient = null

# Register the custom element
unless customElements.get 'x-fastfetch'
    customElements.define 'x-fastfetch', XFastfetchElement

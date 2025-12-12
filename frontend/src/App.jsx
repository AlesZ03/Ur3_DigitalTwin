import React, { useState, useEffect } from 'react';
import { RefreshCw, Database, Clock, FileText, AlertCircle, Send } from 'lucide-react';

export default function RobotLogsDashboard() {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedDate, setSelectedDate] = useState(new Date().toISOString().split('T')[0]);
  const [lastUpdate, setLastUpdate] = useState(null);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [commandInput, setCommandInput] = useState('');
  const [sending, setSending] = useState(false);
  const [commandStatus, setCommandStatus] = useState(null);

  const API_URL = process.env.REACT_APP_API_URL || 'https://your-api-id.execute-api.region.amazonaws.com/prod/logs';
  const COMMAND_API_URL = process.env.REACT_APP_COMMAND_API_URL || 'https://your-api-id.execute-api.region.amazonaws.com/prod/command';

  const fetchLogs = async (date = selectedDate) => {
    setLoading(true);
    setError(null);

    // Quick safety check: ensure the API URL was configured at build time
    if (!API_URL || API_URL.includes('your-api-id') || API_URL.includes('execute-api.region.amazonaws.com')) {
      setLoading(false);
      setError('Frontend not configured: please set REACT_APP_API_URL in .env.production or Amplify env vars and rebuild.');
      return;
    }

    try {
      const dateParam = date.replace(/-/g, '/');
      const response = await fetch(`${API_URL}?date=${dateParam}&limit=500`);
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`);
      }
      
      const data = await response.json();
      
      if (data.success) {
        setLogs(data.logs || []);
        setLastUpdate(new Date().toLocaleTimeString());
      } else {
        throw new Error(data.error || 'Failed to fetch logs');
      }
    } catch (err) {
      console.error('Error fetching logs:', err);
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLogs();
  }, [selectedDate]);

  useEffect(() => {
    if (!autoRefresh) return;

    const interval = setInterval(() => {
      fetchLogs();
    }, 10000); // 10 másodpercenként

    return () => clearInterval(interval);
  }, [autoRefresh, selectedDate]);

  const formatTimestamp = (timestamp) => {
    if (!timestamp) return 'N/A';
    try {
      const date = new Date(timestamp);
      return date.toLocaleString('hu-HU');
    } catch {
      return timestamp;
    }
  };

  const sendCommand = async (command) => {
    setSending(true);
    setCommandStatus(null);

    if (!COMMAND_API_URL || COMMAND_API_URL.includes('your-api-id') || COMMAND_API_URL.includes('execute-api.region.amazonaws.com')) {
      setCommandStatus({ type: 'error', message: 'Frontend not configured: set REACT_APP_COMMAND_API_URL and rebuild.' });
      setSending(false);
      return;
    }

    try {
      const response = await fetch(COMMAND_API_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ command })
      });

      const data = await response.json();

      if (data.success) {
        setCommandStatus({
          type: 'success',
          message: 'Command sent successfully!',
          details: data
        });
        setTimeout(() => setCommandStatus(null), 5000);
      } else {
        throw new Error(data.error || 'Failed to send command');
      }
    } catch (err) {
      setCommandStatus({
        type: 'error',
        message: err.message
      });
    } finally {
      setSending(false);
    }
  };

  const handleSendCustomCommand = () => {
    if (!commandInput.trim()) return;
    try {
      const command = JSON.parse(commandInput);
      sendCommand(command);
      setCommandInput('');
    } catch (err) {
      setCommandStatus({
        type: 'error',
        message: 'Invalid JSON format'
      });
    }
  };

  const quickCommands = [
    { label: 'Home', command: { action: 'home' } },
    { label: 'Stop', command: { action: 'stop' } },
    { label: 'Move Up', command: { action: 'move', axis: 'z', value: 10 } },
    { label: 'Move Down', command: { action: 'move', axis: 'z', value: -10 } }
  ];

  const renderRobotData = (data) => {
    if (!data) return <span className="text-gray-500">No data</span>;

    return (
      <div className="space-y-2">
        {data.x !== undefined && (
          <div className="grid grid-cols-3 gap-2 text-sm">
            <div>
              <span className="text-gray-400">X:</span>
              <span className="ml-2 text-blue-400 font-mono">{data.x?.toFixed(2)}</span>
            </div>
            <div>
              <span className="text-gray-400">Y:</span>
              <span className="ml-2 text-green-400 font-mono">{data.y?.toFixed(2)}</span>
            </div>
            <div>
              <span className="text-gray-400">Z:</span>
              <span className="ml-2 text-purple-400 font-mono">{data.z?.toFixed(2)}</span>
            </div>
          </div>
        )}
        
        {data.joints && (
          <div className="text-xs">
            <span className="text-gray-400">Joints:</span>
            <span className="ml-2 text-gray-300 font-mono">
              [{data.joints.map(j => j?.toFixed(1)).join(', ')}]
            </span>
          </div>
        )}
        
        {data.status && (
          <div className="text-xs">
            <span className="text-gray-400">Status:</span>
            <span className="ml-2 text-green-400">{data.status}</span>
          </div>
        )}

        {Object.keys(data).filter(k => !['x', 'y', 'z', 'joints', 'status'].includes(k)).length > 0 && (
          <details className="text-xs">
            <summary className="text-gray-400 cursor-pointer hover:text-gray-300">
              More data...
            </summary>
            <pre className="mt-2 text-gray-300 font-mono overflow-x-auto">
              {JSON.stringify(data, null, 2)}
            </pre>
          </details>
        )}
      </div>
    );
  };

  return (
  <div className="min-h-screen bg-gradient-to-br from-gray-900 via-gray-800 to-gray-900 text-white p-6">
    <div className="max-w-7xl mx-auto">

      {/* Header */}
      <div className="mb-8">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-3">
            <Database className="w-10 h-10 text-blue-400" />
            <div>
              <h1 className="text-3xl font-bold">Robot Logs Dashboard</h1>
              <p className="text-gray-400">View robot data from S3 storage</p>
            </div>
          </div>

          <div className="flex items-center gap-4">
            {lastUpdate && (
              <div className="flex items-center gap-2 text-sm text-gray-400">
                <Clock className="w-4 h-4" />
                <span>Last update: {lastUpdate}</span>
              </div>
            )}
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={autoRefresh}
                onChange={(e) => setAutoRefresh(e.target.checked)}
                className="w-4 h-4"
              />
              <span className="text-sm">Auto-refresh</span>
            </label>
          </div>
        </div>

        {/* Controls */}
        <div className="flex items-center gap-4 bg-gray-800 p-4 rounded-lg border border-gray-700">
          <div className="flex items-center gap-2">
            <label className="text-sm text-gray-400">Date:</label>
            <input
              type="date"
              value={selectedDate}
              onChange={(e) => setSelectedDate(e.target.value)}
              className="px-3 py-2 bg-gray-900 border border-gray-700 rounded-lg text-white outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          <button
            onClick={() => fetchLogs()}
            disabled={loading}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 rounded-lg transition"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
            Refresh
          </button>
          <div className="ml-auto flex items-center gap-2 text-sm">
            <FileText className="w-4 h-4 text-gray-400" />
            <span className="text-gray-400">
              {logs.length} log{logs.length !== 1 ? 's' : ''}
            </span>
          </div>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="mb-6 p-4 bg-red-900/30 border border-red-500 rounded-lg flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-red-400 flex-shrink-0 mt-0.5" />
          <div>
            <div className="font-medium text-red-400">Error loading logs</div>
            <div className="text-sm text-red-300 mt-1">{error}</div>
          </div>
        </div>
      )}

      {/* Command Status */}
      {commandStatus && (
        <div className={`mb-6 p-4 rounded-lg flex items-start gap-3 ${
          commandStatus.type === 'success' ? 'bg-green-900/30 border border-green-500' : 'bg-red-900/30 border border-red-500'
        }`}>
          <AlertCircle className={`w-5 h-5 flex-shrink-0 mt-0.5 ${
            commandStatus.type === 'success' ? 'text-green-400' : 'text-red-400'
          }`} />
          <div>
            <div className={`font-medium ${
              commandStatus.type === 'success' ? 'text-green-400' : 'text-red-400'
            }`}>
              {commandStatus.message}
            </div>
            {commandStatus.details && (
              <div className="text-sm text-gray-300 mt-1 font-mono">
                Message ID: {commandStatus.details.messageId}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Main Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">

        {/* Logs */}
        <div className="lg:col-span-2">
          {loading && logs.length === 0 ? (
            <div className="text-center py-20">
              <RefreshCw className="w-12 h-12 text-blue-400 animate-spin mx-auto mb-4" />
              <p className="text-gray-400">Loading logs...</p>
            </div>
          ) : logs.length === 0 ? (
            <div className="text-center py-20 bg-gray-800 rounded-xl border border-gray-700">
              <FileText className="w-16 h-16 text-gray-600 mx-auto mb-4" />
              <p className="text-xl text-gray-400 mb-2">No logs found</p>
              <p className="text-sm text-gray-500">Try selecting a different date or wait for robot data</p>
            </div>
          ) : (
            <div className="space-y-4">
              {logs.map((log, index) => (
                <div key={log.key || index} className="bg-gray-800 rounded-xl p-6 border border-gray-700 hover:border-gray-600 transition">
                  <div className="flex items-start justify-between mb-4">
                    <div>
                      <div className="text-sm text-gray-400 mb-1">{formatTimestamp(log.timestamp)}</div>
                      {log.message_id && <div className="text-xs text-gray-500 font-mono">ID: {log.message_id}</div>}
                    </div>
                    <div className="text-xs text-gray-500">{(log.size / 1024).toFixed(2)} KB</div>
                  </div>
                  <div className="bg-gray-900 rounded-lg p-4">{renderRobotData(log.data)}</div>
                  <div className="mt-3 text-xs text-gray-500">S3 Key: {log.key}</div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Commands */}
        <div className="bg-gray-800 rounded-xl p-6 border border-gray-700">
          <div className="flex items-center gap-2 mb-4">
            <Send className="w-5 h-5 text-blue-400" />
            <h2 className="text-xl font-semibold">Send Commands</h2>
          </div>

          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              {quickCommands.map((cmd, i) => (
                <button
                  key={i}
                  onClick={() => sendCommand(cmd.command)}
                  disabled={sending}
                  className="px-4 py-3 bg-blue-600 hover:bg-blue-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-lg font-medium transition text-sm"
                >
                  {cmd.label}
                </button>
              ))}
            </div>

            <div className="space-y-2">
              <label className="text-sm text-gray-400">Custom JSON Command</label>
              <textarea
                value={commandInput}
                onChange={(e) => setCommandInput(e.target.value)}
                placeholder='{"action": "move", "x": 100, "y": 50}'
                className="w-full px-3 py-2 bg-gray-900 border border-gray-700 rounded-lg focus:ring-2 focus:ring-blue-500 outline-none font-mono text-sm"
                rows="4"
                disabled={sending}
              />
              <button
                onClick={handleSendCustomCommand}
                disabled={sending || !commandInput.trim()}
                className="w-full px-4 py-2 bg-green-600 hover:bg-green-700 disabled:bg-gray-700 disabled:text-gray-500 rounded-lg font-medium transition flex items-center justify-center gap-2"
              >
                {sending ? (
                  <>
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    Sending...
                  </>
                ) : (
                  <>
                    <Send className="w-4 h-4" />
                    Send Command
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
);

}
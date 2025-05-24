import { useState, useEffect } from 'react';
import { Ticket, Plus, X, Check, AlertTriangle, Clipboard, RefreshCw } from 'lucide-react';
import { Card } from '../ui/card';
import { supabase } from '../../lib/supabase';
import { useSupabase } from '../../contexts/SupabaseContext';

interface LaunchCode {
  id: string;
  code: string;
  max_uses: number;
  uses_count: number;
  created_at: string;
  promotion: string | null;
  is_active: boolean;
}

export function LaunchCodeManager() {
  const [launchCodes, setLaunchCodes] = useState<LaunchCode[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [newCode, setNewCode] = useState('');
  const [maxUses, setMaxUses] = useState(10);
  const [promotion, setPromotion] = useState('');
  const [formLoading, setFormLoading] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);
  const [copiedCode, setCopiedCode] = useState<string | null>(null);
  const { user } = useSupabase();

  // Check if user is admin
  const [isAdmin, setIsAdmin] = useState(false);
  
  useEffect(() => {
    const checkAdminStatus = async () => {
      if (!user) return;
      
      // For demo purposes, we'll consider specific users as admins
      // In a real app, you'd check against a proper admin role
      const adminEmails = ['admin@healthrocket.app', 'clay@healthrocket.life'];
      setIsAdmin(adminEmails.includes(user.email || ''));
    };
    
    checkAdminStatus();
  }, [user]);

  const fetchLaunchCodes = async () => {
    try {
      setLoading(true);
      setError(null);
      
      const { data, error } = await supabase
        .from('launch_codes')
        .select('*')
        .order('created_at', { ascending: false });
      
      if (error) throw error;
      
      setLaunchCodes(data || []);
    } catch (err) {
      console.error('Error fetching launch codes:', err);
      setError('Failed to load launch codes');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isAdmin) {
      fetchLaunchCodes();
    }
  }, [isAdmin]);

  const handleCreateCode = async () => {
    try {
      setFormLoading(true);
      setFormError(null);
      
      if (!newCode.trim()) {
        setFormError('Launch code is required');
        return;
      }
      
      if (maxUses <= 0) {
        setFormError('Maximum uses must be greater than 0');
        return;
      }
      
      const { data, error } = await supabase
        .from('launch_codes')
        .insert({
          code: newCode.toUpperCase(),
          max_uses: maxUses,
          promotion: promotion || null,
          is_active: true
        })
        .select()
        .single();
      
      if (error) {
        if (error.code === '23505') { // Unique violation
          throw new Error('This launch code already exists');
        }
        throw error;
      }
      
      setLaunchCodes([data, ...launchCodes]);
      setShowCreateForm(false);
      setNewCode('');
      setMaxUses(10);
      setPromotion('');
    } catch (err) {
      console.error('Error creating launch code:', err);
      setFormError(err instanceof Error ? err.message : 'Failed to create launch code');
    } finally {
      setFormLoading(false);
    }
  };

  const toggleCodeStatus = async (id: string, currentStatus: boolean) => {
    try {
      const { error } = await supabase
        .from('launch_codes')
        .update({ is_active: !currentStatus })
        .eq('id', id);
      
      if (error) throw error;
      
      setLaunchCodes(launchCodes.map(code => 
        code.id === id ? { ...code, is_active: !currentStatus } : code
      ));
    } catch (err) {
      console.error('Error toggling launch code status:', err);
      setError('Failed to update launch code');
    }
  };

  const copyToClipboard = async (code: string) => {
    try {
      await navigator.clipboard.writeText(code);
      setCopiedCode(code);
      setTimeout(() => setCopiedCode(null), 2000);
    } catch (err) {
      console.error('Failed to copy code:', err);
    }
  };

  if (!isAdmin) {
    return (
      <Card className="p-4">
        <div className="flex items-center justify-center gap-2 text-gray-400">
          <AlertTriangle size={20} />
          <span>Admin access required</span>
        </div>
      </Card>
    );
  }

  return (
    <Card className="p-4">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Ticket className="text-orange-500" size={20} />
          <h3 className="text-lg font-semibold text-white">Launch Codes</h3>
        </div>
        <div className="flex gap-2">
          <button
            onClick={fetchLaunchCodes}
            className="flex items-center gap-1 px-2 py-1 text-xs text-gray-300 hover:text-white bg-gray-700 hover:bg-gray-600 rounded transition-colors"
          >
            <RefreshCw size={14} />
            <span>Refresh</span>
          </button>
          <button
            onClick={() => setShowCreateForm(true)}
            className="flex items-center gap-2 px-3 py-1.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600"
          >
            <Plus size={16} />
            <span>Create Code</span>
          </button>
        </div>
      </div>

      {error && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-lg p-3 mb-4 text-red-400 text-sm flex items-start gap-2">
          <AlertTriangle size={16} className="mt-0.5 shrink-0" />
          <span>{error}</span>
        </div>
      )}

      {showCreateForm && (
        <div className="bg-gray-700/50 rounded-lg p-4 mb-4">
          <div className="flex justify-between items-center mb-3">
            <h4 className="text-white font-medium">Create New Launch Code</h4>
            <button
              onClick={() => setShowCreateForm(false)}
              className="text-gray-400 hover:text-gray-300"
            >
              <X size={16} />
            </button>
          </div>
          
          <div className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Launch Code
              </label>
              <input
                type="text"
                value={newCode}
                onChange={(e) => setNewCode(e.target.value.toUpperCase())}
                placeholder="e.g. PREVIEW100"
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Maximum Uses
              </label>
              <input
                type="number"
                value={maxUses}
                onChange={(e) => setMaxUses(parseInt(e.target.value) || 0)}
                min="1"
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-gray-300 mb-1">
                Promotion (Optional)
              </label>
              <input
                type="text"
                value={promotion}
                onChange={(e) => setPromotion(e.target.value)}
                placeholder="e.g. Preview Access"
                className="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-lg text-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
            </div>

            {formError && (
              <div className="text-sm text-red-400">{formError}</div>
            )}

            <div className="flex justify-end gap-3">
              <button
                onClick={() => setShowCreateForm(false)}
                className="px-3 py-1.5 text-gray-400 hover:text-white"
              >
                Cancel
              </button>
              <button
                onClick={handleCreateCode}
                disabled={formLoading}
                className="px-3 py-1.5 bg-orange-500 text-white rounded-lg hover:bg-orange-600 disabled:opacity-50"
              >
                {formLoading ? 'Creating...' : 'Create Code'}
              </button>
            </div>
          </div>
        </div>
      )}

      {loading ? (
        <div className="flex items-center justify-center py-8">
          <div className="animate-spin rounded-full h-8 w-8 border-t-2 border-b-2 border-orange-500" />
        </div>
      ) : launchCodes.length === 0 ? (
        <div className="text-center py-8 text-gray-400">
          <Ticket className="mx-auto mb-2" size={24} />
          <p>No launch codes found</p>
          <p className="text-sm text-gray-500 mt-2">Create your first launch code to get started</p>
        </div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="text-xs text-gray-400 uppercase">
              <tr>
                <th className="px-4 py-2">Code</th>
                <th className="px-4 py-2">Uses</th>
                <th className="px-4 py-2">Promotion</th>
                <th className="px-4 py-2">Created</th>
                <th className="px-4 py-2">Status</th>
                <th className="px-4 py-2">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-700">
              {launchCodes.map((code) => (
                <tr key={code.id} className="hover:bg-gray-700/50">
                  <td className="px-4 py-3">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-white">{code.code}</span>
                      <button
                        onClick={() => copyToClipboard(code.code)}
                        className="text-gray-400 hover:text-white"
                        title="Copy code"
                      >
                        {copiedCode === code.code ? (
                          <Check size={14} className="text-lime-500" />
                        ) : (
                          <Clipboard size={14} />
                        )}
                      </button>
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    <span className={code.uses_count >= code.max_uses ? 'text-red-400' : 'text-gray-300'}>
                      {code.uses_count} / {code.max_uses}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-gray-300">
                    {code.promotion || '-'}
                  </td>
                  <td className="px-4 py-3 text-gray-400 text-xs">
                    {new Date(code.created_at).toLocaleDateString()}
                  </td>
                  <td className="px-4 py-3">
                    <span className={`px-2 py-1 text-xs rounded-full ${
                      code.is_active 
                        ? 'bg-lime-500/20 text-lime-500' 
                        : 'bg-red-500/20 text-red-400'
                    }`}>
                      {code.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => toggleCodeStatus(code.id, code.is_active)}
                      className={`px-2 py-1 text-xs rounded ${
                        code.is_active
                          ? 'bg-gray-700 text-gray-300 hover:bg-red-500/20 hover:text-red-400'
                          : 'bg-gray-700 text-gray-300 hover:bg-lime-500/20 hover:text-lime-500'
                      }`}
                    >
                      {code.is_active ? 'Deactivate' : 'Activate'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Card>
  );
}
import React, { useState, useEffect } from 'react';
import { Heart, Activity, Rocket, Info, Crown, Gift, Target, Palette, Trophy, X, Plus, Zap, Flame, Calendar, Award } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { MetricCard } from './MetricCard';
import { HealthDashboard } from '../../health/HealthDashboard';
import { VitalSetup } from '../../health/VitalSetup';
import { Tooltip } from '../../ui/tooltip';
import { useHealthAssessment } from '../../../hooks/useHealthAssessment';
import { useSupabase } from '../../../contexts/SupabaseContext';
import { useCosmo } from '../../../contexts/CosmoContext';

interface LevelUpModalProps {
  level: number;
  onClose: () => void;
}

function LevelUpModal({ level, onClose }: LevelUpModalProps) {
  return (
    <div className="fixed inset-0 bg-black/90 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-gray-800 rounded-lg max-w-lg w-full p-6 relative">
        <button
          onClick={onClose}
          className="absolute top-4 right-4 text-gray-400 hover:text-white"
        >
          <X size={20} />
        </button>

        <div className="text-center mb-8">
          <div className="flex items-center justify-center gap-2 mb-2">
            <Crown className="text-orange-500" size={28} />
            <h2 className="text-2xl font-bold text-white">Blastoff!</h2>
          </div>
          <p className="text-lg text-gray-300">You've reached Level {level}</p>
        </div>

        <div>
          <h3 className="text-lg font-semibold text-white mb-4 flex items-center gap-2">
            <Gift className="text-orange-500" size={20} />
            <span>Keep Earning FP to Unlock</span>
          </h3>
          <div className="grid grid-cols-1 gap-4">
            <div className="bg-gray-700/50 p-4 rounded-lg">
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <Target size={18} className="text-orange-500 mt-1 shrink-0" />
                  <div>
                    <p className="text-white">New Features at Higher Levels</p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <Palette size={18} className="text-orange-500 mt-1 shrink-0" />
                  <div>
                    <p className="text-white">Custom Rocket Colors, Decals & Effects</p>
                  </div>
                </div>
                <div className="flex items-start gap-3">
                  <Trophy size={18} className="text-orange-500 mt-1 shrink-0" />
                  <div>
                    <p className="text-white">New Challenges & Quests</p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

interface DashboardHeaderProps {
  healthSpanYears: number;
  healthScore: number;
  days_since_fp: number;
  nextLevelPoints: number;
  level: number;
}

export function DashboardHeader({ 
  healthSpanYears, 
  healthScore, 
  days_since_fp,
  nextLevelPoints,
  level
}: DashboardHeaderProps) {
  const navigate = useNavigate();
  const [showHealthDashboard, setShowHealthDashboard] = useState(false);
  const [showLevelModal, setShowLevelModal] = useState(false);
  const [hasSeenLevelModal, setHasSeenLevelModal] = useState(() => {
    return localStorage.getItem('hasSeenLevelModal') === 'true';
  });
  const [showPreview100Challenge, setShowPreview100Challenge] = useState(false);
  const { user, supabase } = useSupabase();
  const { showCosmo } = useCosmo();
  const { canUpdate } = useHealthAssessment(user?.id);
  const [showVitalSetup, setShowVitalSetup] = useState(false);
  const [currentVitalUserId, setCurrentVitalUserId] = useState(null);
  const [getVitalUserLoading, setGetVitalUserLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // CHECK EXISTING VITAL USER
  const checkExistingVitalUser = async () => {
    // Reset any previous error state
    setError(null);

    // Check if both user and supabase client are available
    if (!user?.id || !supabase) {
      console.log('User or Supabase client not initialized');
      return;
    }

    try {
      setGetVitalUserLoading(true);
      
      // Use a try-catch block to handle potential errors
      try {
        const { data: vitalData, error: vitalError } = await supabase.rpc(
          "get_vital_user",
          {
            p_user_id: user.id,
          }
        );

        if (vitalError) throw vitalError;

        if (vitalData?.vital_user_id) {
          setCurrentVitalUserId(vitalData?.vital_user_id);
        }

        // Try to sync vital user, but don't throw if it fails
        try {
          const { error: syncError } = await supabase.rpc("sync_vital_user", {
            p_user_id: user.id,
          });

          if (syncError) {
            console.warn("Non-critical error syncing Vital user:", syncError);
          }
        } catch (syncErr) {
          console.warn("Non-critical error in Vital sync:", syncErr);
          // Don't rethrow, as this is a non-critical operation
        }
      } catch (vitalErr) {
        console.error("Error getting Vital user:", vitalErr);
        setError("Failed to retrieve Vital user data");
        // Set to null but don't throw, as we want to continue even if this fails
        setCurrentVitalUserId(null);
      }
    } catch (err) {
      console.error("Unexpected error in checkExistingVitalUser:", err);
      setError("An unexpected error occurred");
      setCurrentVitalUserId(null);
    } finally {
      setGetVitalUserLoading(false);
    }
  };

  useEffect(() => {
    // Only run the check if we have both user and supabase client
    if (user?.id && supabase) {
      checkExistingVitalUser();
    }
  }, [user?.id, supabase]); // Add supabase to dependency array

  const handleDataTrackingClick = () => {
    if (!currentVitalUserId) {
      setShowVitalSetup(true);
    } else {
      navigate("/connect-device");
    }
  };

  const handleShowLevelModal = () => {
    setShowLevelModal(true);
    setHasSeenLevelModal(true);
    localStorage.setItem('hasSeenLevelModal', 'true');
  };

  return (
    <div  id="rocket">
      <div className="bg-gray-800 py-4 sm:py-5 border-b border-gray-700 relative">
        <div className="max-w-6xl mx-auto px-4 relative">
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-center gap-3 sm:gap-6">
            {/* Beta indicator */}
            <div className="absolute -top-5 right-4">
              <div className="bg-black/20 backdrop-blur-sm px-2 py-0.5 rounded text-xs font-medium text-orange-500 border border-orange-500/30">
                Preview v2.27
              </div>
            </div>
            <button 
              onClick={() => setShowHealthDashboard(true)}
              className="flex-1 max-w-[200px]"
            >
              <MetricCard
                icon={<Heart size={20} className="text-orange-500" />}
                label="+HealthSpan"
                value={`+${healthSpanYears.toFixed(1)} yrs`}
                showNotification={canUpdate}
              />
            </button>
            <button 
              onClick={() => setShowHealthDashboard(true)}
              className="flex-1 max-w-[200px]"
            >
              <MetricCard
                icon={<Activity size={20} className="text-lime-500" />}
                label="HealthScore"
                value={healthScore.toString()}
                showNotification={canUpdate}
              />
            </button>
            <button 
              onClick={handleShowLevelModal}
              className="flex-1 max-w-[200px]"
            >
              <MetricCard
                icon={<Rocket size={20} className="text-orange-500" />}
                label="Level"
                value={level.toString()}
                showClickIndicator={!hasSeenLevelModal}
              />
            </button>
            </div>
            
            <button 
              onClick={handleDataTrackingClick}
              className="flex items-center justify-center gap-2 text-sm text-orange-500 hover:text-orange-400 transition-colors"
            >
              <div className="w-5 h-5 bg-orange-500 rounded-full flex items-center justify-center animate-pulse">
                <Plus size={12} className="text-white" />
              </div>
              <span className="text-xs">Connect Devices for FP Bonus and HealthScore Level Ups</span>
            </button>
          </div>
          
          {/* Days Since FP Indicator */}
          {days_since_fp > 0 && (
            <div className="flex items-center justify-center mt-1">
              <div className="flex items-center gap-1 text-xs text-orange-500">
                <Zap size={12} className="animate-pulse" />
                <span>{days_since_fp} {days_since_fp === 1 ? 'day' : 'days'} since last Fuel Points earned</span>
              </div>
            </div>
          )}

          {/* Error Message */}
          {error && (
            <div className="mt-2 text-center text-red-500 text-sm">
              {error}
            </div>
          )}
          
          <div className="flex justify-center mt-1">
            <button 
              onClick={() => setShowPreview100Challenge(true)}
              className="flex items-center justify-center gap-2 text-sm text-orange-500 hover:text-orange-400 transition-colors"
            >
              <Info size={14} className="text-orange-500" />
              <span className="text-xs">Preview 100 Challenge</span>
            </button>
          </div>
        </div>
        
      </div>

      {showHealthDashboard && (
        <HealthDashboard
          healthSpanYears={healthSpanYears}
          healthScore={healthScore}
          nextLevelFP={nextLevelPoints}
          onClose={() => setShowHealthDashboard(false)}
        />
      )}
      {showLevelModal && (
        <LevelUpModal
          level={level}
          onClose={() => setShowLevelModal(false)}
        />
      )}
      
      {/* Preview 100 Challenge Modal */}
      {showPreview100Challenge && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-gray-800 rounded-lg max-w-2xl w-full p-6 space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <Flame className="text-orange-500" size={24} />
                <h2 className="text-xl font-bold text-white">Preview 100 Challenge</h2>
              </div>
              <button
                onClick={() => setShowPreview100Challenge(false)}
                className="text-gray-400 hover:text-white transition-colors"
              >
                <X size={20} />
              </button>
            </div>
            
            <div className="space-y-6">
              <div className="bg-gray-700/50 rounded-lg p-4">
                <h3 className="text-lg font-medium text-white flex items-center gap-2 mb-4">
                  <Flame className="text-orange-500" size={20} />
                  Challenge Requirements
                </h3>
                <p className="text-sm text-gray-300 mb-3">
                  Complete a 42-Day Burn Streak, earning at least 1 Fuel Point each day for 42 consecutive days. 
                  Must be completed during June 1 to July 30, 2025.
                </p>
              </div>

              <div className="bg-gray-700/50 rounded-lg p-4">
                <h3 className="text-lg font-medium text-white flex items-center gap-2 mb-4">
                  <Award className="text-orange-500" size={20} />
                  Rewards
                </h3>
                <p className="text-sm text-gray-300 mb-3">
                  Secure 2,500 equity shares upon completion with a chance to win up to 100,000 additional shares.
                  Bonus shares will be awarded based on longest streaks and most FP earned during preview period.
                </p>
              </div>
              
              <div className="bg-gray-700/50 rounded-lg p-4">
                <h3 className="text-lg font-medium text-white flex items-center gap-2 mb-4">
                  <Calendar className="text-orange-500" size={20} />
                  Alternative Eligibility
                </h3>
                <p className="text-sm text-gray-300">
                  Players who don't complete the 42-Day Burn Streak will still be eligible to win prizes from 
                  Wellness Partners based on their Fuel Points earned during the preview period.
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
      
      {/* Vital Setup Modal */}
      {showVitalSetup && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-[60] flex items-start justify-center p-4 overflow-y-auto">
          <div className="bg-gray-800 rounded-lg max-w-4xl w-full my-8 shadow-xl">
            <VitalSetup
              onComplete={() => {
                setShowVitalSetup(false);
                navigate("/connect-device");
              }}
              onClose={() => setShowVitalSetup(false)}
            />
          </div>
        </div>
      )}
    </div>
  );
}
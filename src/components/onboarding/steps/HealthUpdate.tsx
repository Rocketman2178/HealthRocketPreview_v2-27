import React, { useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { useSupabase } from '../../../contexts/SupabaseContext';
import { calculateHealthScore } from '../../../lib/health/calculators/score';
import { HealthUpdateForm } from '../../health/HealthUpdateForm';
import { ArrowRight } from 'lucide-react';
import type { CategoryScores, Gender } from '../../../lib/health/types';
import { DatabaseError } from '../../../lib/errors';

interface HealthUpdateData {
  expectedLifespan: number;
  expectedHealthspan: number;
  gender: Gender;
  categoryScores: CategoryScores;
  healthGoals?: string;
}

interface HealthUpdateProps {
  onComplete?: () => void;
}

export function HealthUpdate({ onComplete }: HealthUpdateProps) {
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState<HealthUpdateData>({
    expectedLifespan: 85,
    expectedHealthspan: 75,
    gender: 'Male',
    categoryScores: {
      mindset: 5,
      sleep: 5,
      exercise: 5,
      nutrition: 5,
      biohacking: 5
    },
    healthGoals: ''
  });
  const { user } = useSupabase();
  const [error, setError] = useState<Error | null>(null);

  const handleSubmit = async (data: HealthUpdateData) => {
    if (!user) return;

    try {
      setLoading(true);
      setError(null);

      const healthScore = calculateHealthScore(data.categoryScores);
      const now = new Date().toISOString();

      const { data: result, error: transactionError } = await supabase.rpc('update_health_assessment_v3', {
        p_user_id: user.id,
        p_expected_lifespan: data.expectedLifespan,
        p_expected_healthspan: data.expectedHealthspan,
        p_health_score: healthScore,
        p_mindset_score: data.categoryScores.mindset,
        p_sleep_score: data.categoryScores.sleep,
        p_exercise_score: data.categoryScores.exercise,
        p_nutrition_score: data.categoryScores.nutrition,
        p_biohacking_score: data.categoryScores.biohacking,
        p_created_at: now,
        p_gender: data.gender,
        p_health_goals: data.healthGoals
      });
      
      if (transactionError) {
        throw new DatabaseError('Failed to update health assessment', transactionError);
      }

      // Wait for transaction to complete
      await new Promise(resolve => setTimeout(resolve, 1000));

      // Trigger refresh events
      window.dispatchEvent(new CustomEvent('onboardingCompleted'));
      window.dispatchEvent(new CustomEvent('dashboardUpdate'));
      window.dispatchEvent(new CustomEvent('healthUpdate'));

      if (onComplete) {
        onComplete();
      }
    } catch (error) {
      console.error('Error updating health:', error);
      setError(error instanceof Error ? error : new DatabaseError('Failed to complete onboarding'));
      return; // Don't proceed on error
    } finally {
      setLoading(false);
    }
  };

  return (
    <>
      <HealthUpdateForm 
        onClose={() => {}} // Not needed for onboarding
        onSubmit={handleSubmit}
        loading={loading}
        error={error}
        isOnboarding={true}
        buttonText="Complete Assessment"
      />
    </>
  );
}
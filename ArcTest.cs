
using UnityEngine;

public static class ArcTest
{

    public static bool TargetArcTest(Transform myship, Vector3 targetPosition, float startDegree, float stopDegree)
    {
        Vector3 leftArcNormalized = Quaternion.Euler(0, startDegree, 0) * myship.forward;
        Vector3 RightArcNormalized = Quaternion.Euler(0, stopDegree, 0) * myship.forward;
        Vector3 targetNormalized = (targetPosition - myship.position).normalized;

        //Debug.DrawLine(myship.position, leftArcNormalized * 5 + myship.position, Color.yellow, 5);
        //Debug.DrawLine(myship.position, RightArcNormalized * 5 + myship.position, Color.yellow, 5);

        var offset = (stopDegree - startDegree);

        if (offset == 360f) return true;

        var testResult = TargetArcTest(leftArcNormalized, RightArcNormalized, targetNormalized, offset);

        return testResult;
    }

    public static bool TargetArcTest(Vector3 myPosition, Vector3 myForward, 
        Vector3 targetPosition, float startDegree, float stopDegree, bool debug = false)
    {
        Vector3 leftArcNormalized = Quaternion.Euler(0, startDegree, 0) * myForward;
        Vector3 RightArcNormalized = Quaternion.Euler(0, stopDegree, 0) * myForward;
        Vector3 targetNormalized = (targetPosition - myPosition).normalized;

        if (debug)
        {
            Debug.DrawLine(myPosition, myPosition + leftArcNormalized * 5 + myForward, Color.yellow, 5);
            Debug.DrawLine(myPosition, myPosition + RightArcNormalized * 5 + myForward, Color.yellow, 5);
        }

        var offset = (stopDegree - startDegree);

        if (offset == 360f) return true;

        var testResult = TargetArcTest(leftArcNormalized, RightArcNormalized, targetNormalized, offset);

        return testResult;
    }

    public static bool TargetArcTest(Vector3 leftVector, Vector3 rightVector, Vector3 targetVector, float actualAngle)
    {
        float angle = actualAngle;
        float halfAngle = angle / 2f;

        Vector3 midWayVector = Quaternion.Euler(0, halfAngle, 0) * leftVector;
        float minRangeUnit = Vector3.Dot(midWayVector, rightVector);
        float targetRangeUnit = Vector3.Dot(midWayVector, targetVector);

        return (targetRangeUnit > minRangeUnit);
    }

}